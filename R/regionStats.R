setGeneric("regionStats", function(x, ...){standardGeneric("regionStats")})

.regionStats <- function(diffs, design, ch, sp, maxFDR, n.perm, window, 
                         mean.trim, min.probes, max.gap, two.sides, verbose, return.tm) {

  uch <- unique(ch)

  tmeanReal <- matrix(,nrow=nrow(diffs),ncol=ncol(diffs))
  tmeanPerms <- lapply(1:ncol(design), function(u) matrix(NA, nrow=nrow(diffs), ncol=n.perm))
  if(length(colnames(design)) > 0) names(tmeanPerms) <- colnames(design)
  regions <- fdrTabs <- vector("list", length(tmeanPerms))
  names(regions) <- names(fdrTabs) <- colnames(design)
  
  ifelse( verbose, print(gc()), gc())
  
  
  # calculate smoothed statistics
  for(col in 1:ncol(diffs)) {
  
    if( verbose )
	    message("Calculating trimmed means for column ", col, " of design matrix:")
      
    for(ii in 1:length(uch)) {
      if( verbose )
	      message(" ", uch[ii], "-", sep="")
	    w <- which(ch == uch[ii])
	  
	    tmeanReal[w,col] <- gsmoothr::tmeanC(sp[w], diffs[w,col], probeWindow=window, 
                                           trim=mean.trim, nProbes=min.probes)
  	    if( verbose )
	        message("R")
	    for(j in 1:ncol(tmeanPerms[[col]])) {
	      s <- sample(1:nrow(tmeanReal))
	      tmeanPerms[[col]][w,j] <- gsmoothr::tmeanC(sp[w], diffs[s,col][w], probeWindow=window, 
                                                   trim=mean.trim, nProbes=min.probes)
		    if( verbose )
	        message(".", appendLF = FALSE)

	    }
	  }


    if( verbose )
      message("Calculating FDR table.")
	  mx <- max(abs(tmeanPerms[[col]]),na.rm=TRUE)


    z <- apply(tmeanPerms[[col]], 2, FUN=function(u) .fdrTable(tmeanReal[,col], u, ch, sp, 40, min.probes, max.gap, 
                                                               two.sides, maxCutoff=mx, verbose=verbose))
    fdrTabs[[col]] <- z[[1]]
	  for(i in 2:length(n.perm))
	    fdrTabs[[col]][,2:3] <- fdrTabs[[col]][,2:3] + z[[i]][,2:3]
    # re-adjust FDR calculation over all permutations
	  fdrTabs[[col]]$fdr <- pmin(fdrTabs[[col]]$neg/fdrTabs[[col]]$pos,1)  
	
	  # select lowest cutoff such that FDR is achieved
	  w <- which(fdrTabs[[col]]$fdr < maxFDR )
	  cut <- min( fdrTabs[[col]]$cut[w], na.rm=TRUE )
	
    if( verbose )
      message("Using cutoff of ", cut, " for FDR of ", maxFDR)
	  
	  regions[[col]] <- .getBed(tmeanReal[,col], ch, sp, cut, min.probes, max.gap, two.sides)
  }
  
  if(!return.tm)
  {
    tmeanReal <- NULL
    tmeanPerms <- NULL
  }

  new("RegionStats", list(regions = regions, tmeanReal = tmeanReal, tmeanPerms = tmeanPerms,
                          fdrTables = fdrTabs))
}


#setMethod("regionStats","AffymetrixCelSet",
#    function(x, design = NULL, maxFDR = 0.05, n.perm = 5, window = 600, 
#             mean.trim = 0.1, min.probes = 10, max.gap = 500, two.sides = TRUE, ind = NULL, 
#             return.tm = FALSE, verbose = TRUE)
#{
#    if(is.null(design))
#        stop("Design matrix not provided.")
#
#    cdf <- getCdf(x)
#    
#    if( is.null(ind) )
#      ind <- getCellIndices( cdf, useNames=FALSE, unlist=TRUE)
#
#    if( nrow(design) != nbrOfArrays(x) )
#      stop("The number of rows in the design matrix does not equal the number of columns in the probes data matrix")
#	
#    acp <- AromaCellPositionFile$byChipType(getChipType(cdf))
#    ch <- acp[ind,1,drop=TRUE]
#    sp <- acp[ind,2,drop=TRUE]
#  
#    # cut down on the amount of data read, if some rows of the design matrix are all zeros
#    w <- which( rowSums(design != 0) > 0 )
#    x <- extract(x,w, verbose=verbose)
#    dmP <- log2(extractMatrix(x,cells=ind,verbose=verbose))
#  
#    # compute probe-level score of some contrast
#    diffs <- dmP %*% design[w,]
#
#    w <- rowSums( is.na(diffs) )==0
#    if( verbose )
#        message("Removing ", sum(!w), " rows, due to NAs.")
#	
#    diffs <- diffs[w,,drop=FALSE]
#    ch <- ch[w]
#    sp <- sp[w]
#  
#    rm(dmP)
#    ifelse( verbose, print(gc()), gc())
#
#    return(.regionStats(diffs, design, ch, sp, maxFDR, n.perm, window, mean.trim, 
#           min.probes, max.gap, two.sides, verbose, return.tm))
#})


setMethod("regionStats","matrix",
    function(x, design = NULL, maxFDR = 0.05, n.perm = 5, window = 600, 
             mean.trim = 0.1, min.probes = 10, max.gap = 500, two.sides = TRUE, ndf, 
             return.tm = FALSE, verbose = TRUE)
{
    if(is.null(design))
        stop("Design matrix not provided.")
                                  
    # meant for nimblegen data

    # cut down on the amount of data read, if some rows of the design matrix are all zeros
    w <- which( rowSums(design != 0) > 0 )
    diffs = x %*% design

    w <- rowSums( is.na(diffs) )==0
    if( verbose )
        message("Removing ", sum(!w), " rows, due to NAs.")


    return(.regionStats(diffs, design, gsub("chr","",ndf$chr), ndf$position, maxFDR, 
                        n.perm, window, mean.trim, min.probes, max.gap, two.sides, 
                        verbose, return.tm))
})



# accesory functions
.getBed <- function(score, ch, sp, cut=NULL, min.probes=10, max.gap, two.sides) {
  if( is.null(cut) )
    stop("Need to specify 'cut'.")
  posInd <- .getRegions(score, ch, sp, min.probes, max.gap, cut, two.sides, doJoin=TRUE)
  if( is.null(posInd) )
    return(list())
  posReg <- data.frame(chr=paste("chr",ch[posInd$start],sep=""),
                       start=sp[posInd$start], end=sp[posInd$end], score=0, 
                       startInd=posInd$start, endInd=posInd$end, stringsAsFactors=FALSE)
  for(i in 1:nrow(posInd))
    posReg$score[i] <- round(median(score[ (posInd$start[i]:posInd$end[i]) ]),3)
  posReg
}

.getRegionsChr <- function(ind, score, sp, min.probes, max.gap, cutoff, doJoin) {
  #pad the beginning & end
  probes <- c(FALSE, score[ind] > cutoff, FALSE)

  #insert FALSEs in to break up regions with gaps>max.gap
  probeGaps <- which(diff(sp[ind])>max.gap)
  num.gaps <- length(probeGaps)

  ind.2 <- rep(NA, length(ind)+num.gaps)
  ind.gaps <- probeGaps+1:num.gaps
  ind.nogaps <- (1:length(ind.2))[-ind.gaps]
  ind.2[ind.nogaps] <- ind

  probes.2 <- rep(FALSE, length(probes)+num.gaps)
  probes.gaps <- probeGaps+1:num.gaps+1
  probes.nogaps <- (1:length(probes.2))[-probes.gaps]
  probes.2[probes.nogaps] <- probes
 
  df <- diff(probes.2)
  st <- ind.2[which(df==1)]
  en <- ind.2[which(df==-1)-1]

  #sort starts & ends again
  st <- sort(st)
  en <- sort(en)

  #join regions with < max.gap basepairs between positive probes
  if (doJoin) {
    gap.w <- which(sp[st[-1]]-sp[rev(rev(en)[-1])] < max.gap)
    if (length(gap.w)>0) {
      st <- st[-(gap.w+1)]
       en <- en[-gap.w]
    }
  }

  w <- (en-st+1) >= min.probes
  if (sum(w)==0)
    return(data.frame(start=NULL, end=NULL))
  else
    data.frame(start=st,end=en)[w,]
}


.getRegions <- function(score, ch, sp, min.probes, max.gap, cutoff, two.sides, doJoin) {
  chrInds <- split(1:length(score), ch)
  regTable <- data.frame(start=NULL, end=NULL)
  for (i in 1:length(chrInds)) 
    regTable <- rbind(regTable, .getRegionsChr(chrInds[[i]], score, sp, min.probes, max.gap, cutoff, doJoin))
  if (two.sides)
    for (i in 1:length(chrInds))
      regTable <- rbind(regTable, .getRegionsChr(chrInds[[i]], -score, sp, min.probes, max.gap, cutoff, doJoin))
  return(regTable)
}

.fdrTable <- function(realScore, permScore, ch, sp, cutsLength, min.probes, max.gap, two.sides, 
                      minCutoff = .5, maxCutoff=max( abs(permScore), na.rm=TRUE ), verbose) {
  cuts <- seq(minCutoff,maxCutoff,length=cutsLength)

  fdr <- matrix(,nrow=length(cuts),ncol=4)
  colnames(fdr) <- c("cutoff","neg","pos","fdr")
  for(i in 1:length(cuts)) {
    pos <- nrow(.getRegions(realScore, ch, sp, min.probes, max.gap, cuts[i], two.sides, doJoin=FALSE))
    neg <- nrow(.getRegions(permScore, ch, sp, min.probes, max.gap, cuts[i], two.sides, doJoin=FALSE))
    fdr[i,] <- c(cuts[i],neg,pos,min(neg/pos,1))
    if (verbose) message(".", appendLF = FALSE)
  }
  if (verbose) message("")
  as.data.frame(fdr)
}
