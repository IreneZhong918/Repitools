setGeneric("gcContentCalc", function(x, organism, ...){standardGeneric("gcContentCalc")})

setMethod("gcContentCalc", c("GRanges", "BSgenome"),
    function(x, organism, verbose = TRUE)
{   
    if(verbose) message("Calculating GC content.")
    strand(x) <- "+"
    chrs <- as.character(seqnames(x))
    regionsByChr <- split(x, chrs)
    gcByChr <- lapply(regionsByChr, function(y)
    {
        temp <- getSeq(organism, y, as.character = FALSE)
        tempAlphabet <- alphabetFrequency(temp, as.prob = TRUE)
        tempAlphabet[, "C"] + tempAlphabet[, "G"]
    })
    unsplit(gcByChr, chrs)
})

setMethod("gcContentCalc", c("data.frame", "BSgenome"),
    function(x, organism, window = NULL, ...)
{
    if(is.null(window))
        stop("Window size not given.")

    if (is.null(x$position)) x$position <- ifelse(x$strand == '+', x$start, x$end)
    x <- GRanges(x$chr, IRanges(x$position, width=1), seqlengths=seqlengths(organism)[unique(x$chr)])
    x <- resize(x, window, fix="center")
    gcContentCalc(x, organism, ...)
})
