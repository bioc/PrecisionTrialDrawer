# Given a vector of genes and a vector of tumor type as resulted from showTumorType() or showCancerStudy()
# It returns a nested list composed by n elements, one for each tumor type
# Each element is composed by a CNA df and a vector with all patient barcodes for that tumor type

.getCNA <- function(myGenes=myGenes
                    ,tumor_type="all_tumors"
                    ,block=NULL) {
    mycgds <- cgdsr::CGDS("http://www.cbioportal.org/public-portal/")
    all_cancer_studies <- cgdsr::getCancerStudies(mycgds)[,c(1,2)]
    all_cancer_studies$tumor_type <- sapply(strsplit(all_cancer_studies[,1] , "_") , '[' , 1)
    if(tumor_type[1]=="all_tumors") {
        chosenTumors <- all_cancer_studies[,1]
    } else {
        # chosenTumors <- all_cancer_studies[grepl( paste(tumor_type , collapse="|") 
        #                                     , all_cancer_studies[,1] 
        #                                     , ignore.case=TRUE) , 1]
        chosenTumors <- all_cancer_studies[ all_cancer_studies[,'tumor_type'] %in% tumor_type, 1]
        if(length(chosenTumors)==0){
            chosenTumors <- all_cancer_studies[ all_cancer_studies[,'cancer_study_id'] %in% tumor_type, 1]
        }
    }
    out_double <- lapply(chosenTumors , function(i)
        {
            geneticProfile <- tryCatch({
                cgdsr::getGeneticProfiles(mycgds, i)
            } , error = function(e) {
                 url <- paste(mycgds$.url, "webservice.do?cmd=getGeneticProfiles&&cancer_study_id=", i, sep = "")
                 res <- httr::GET(url)
                 if(res$status_code!=200){
                     stop("Problems with cBioPortal Connection at" %++% url)
                 }
                 df <- strsplit(httr::content(res) , "\n") %>% unlist %>% strsplit("\t")
                 df <- do.call("rbind" , df[-1]) %>% as.data.frame(stringsAsFactors=FALSE) %>% setNames(df[[1]])
                 message("\n")
                 return(df)
                #df <- read.table(url, skip = 0, header = TRUE, as.is = TRUE, sep = "\t", quote = "")
             })
            geneticProfile <- geneticProfile[ ,c(1:2)]
            geneticProfileID <- grep("gistic" , geneticProfile$genetic_profile_id
                                , value=TRUE , ignore.case=TRUE)
            if(length(geneticProfileID)==0){
              geneticProfileID <- grep("cna$" , geneticProfile$genetic_profile_id 
                                     , value=TRUE , ignore.case=TRUE)
            }
            # Unfortunately, cgdsr is very weak and crush frequently
            # In case of 
            caseList <- tryCatch({
                cgdsr::getCaseLists(mycgds, i)
            } , error = function(e) {
                 url <- paste(mycgds$.url, "webservice.do?cmd=getCaseLists&cancer_study_id=", i, sep = "")
                 res <- httr::GET(url)
                 if(res$status_code!=200){
                     stop("Problems with cBioPortal Connection at" %++% url)
                 }
                 df <- strsplit(httr::content(res) , "\n") %>% unlist %>% strsplit("\t")
                 df <- do.call("rbind" , df[-1]) %>% as.data.frame(stringsAsFactors=FALSE) %>% setNames(df[[1]])
                 message("\n")
                 return(df)
                #df <- read.table(url, skip = 0, header = TRUE, as.is = TRUE, sep = "\t", quote = "")
             })
            # This definition changes often, keep the pace
            sel <- caseList$case_list_name %in% c("Tumors log2 copy-number" 
            									, "Tumor Samples with CNA data")
            if(any(sel)) {
                if(is.null(block)){
                    message(paste("getting CNA from this cancer study:" , i ))
                } else {
                    message(paste("getting CNA from this cancer study:" , i, paste0("(" , block , ")")))
                }
                if(length(which(sel))>1)
                	sel <- which(sel)[1]
                caseListID <- caseList[sel, 1]
                error <- tryCatch(
                    cna <- cgdsr::getProfileData( mycgds 
                        , caseList=caseListID 
                        , geneticProfile=geneticProfileID
                        , genes=myGenes)
                    , error=function(e) {
                        message(paste("Impossible to retrive CNA from" , i , "study"))
                        return(e)
                        }
                    )
                # if(error$message=="object 'myGenes' not found") stop("No gene data provided")
                if(!exists("cna")) {
                  cna <- NULL
                  patients <- NULL
                } else if(nrow(cna) == 0 ){
                  cna <- NULL
                  patients <- NULL
                } else {
                    patients <- strsplit(caseList[sel, 'case_ids'] , split=" ")[[1]]
                }
            } else {
                # message(paste("No CNA data from" , i , "study"))
                cna <- NULL
                patients <- NULL
            }
            return( list( out=cna , patients=patients) )
        })
        names(out_double) <- chosenTumors
        return(out_double)
}

.subsetCNA <- function(panel , cna_full)
{
    panel_cna <- panel[ panel$alteration=="CNA" , ]
    cna_subset <- merge(cna_full , panel_cna , all.x=TRUE , by="gene_symbol")
    cna_subset <- cna_subset[ !is.na(cna_subset$group) , ] # there should be no NA, but who knowns
    idx_ok <- ifelse( cna_subset$CNA==cna_subset$exact_alteration | 
                     (cna_subset$exact_alteration=="" & cna_subset$CNA %in% c("amplification" , "deletion")), TRUE , FALSE)
    cna_subset <- cna_subset[ idx_ok , ] %>% 
                    unique %>% 
                    .[ , c("drug" , "group" , "gene_symbol" , "tumor_type" , "case_id")]
    if(nrow(cna_subset)>0){
      cna_subset$alteration_id <- paste0("cna_" , 1:nrow(cna_subset))
    } else {
      cna_subset$alteration_id <- character(0)
    }
    return(cna_subset)
}