#' @title sctype source files
#' @name sctype_source
#' @description loads sctype functions needed for an automated cell type annotation . 
#' @details none
#' @param none 
#' @return original ScType database
#' @export
#' @examples
#' db_=sctype_source()
#' 
sctype_source <- function(){
    # load tissue auto detect
    source("https://raw.githubusercontent.com/IanevskiAleksandr/sc-type/master/R/auto_detect_tissue_type.R")
    # load gene set preparation function
    source("https://raw.githubusercontent.com/IanevskiAleksandr/sc-type/master/R/gene_sets_prepare.R")
    # load cell type annotation function
    source("https://raw.githubusercontent.com/IanevskiAleksandr/sc-type/master/R/sctype_score_.R")
    # load ScType database
    db_ = "https://raw.githubusercontent.com/IanevskiAleksandr/sc-type/master/ScTypeDB_full.xlsx"
    return(db_)
}

#' @title Run sctype analysis on Seurat object
#' @name run_scType
#' @description run an automated cell type annotation 
#' @details This function is compatible with seurat versions 4 and 5 -- different methods(@,$) to retrieve counts,data,scale.data
#' @param seurat_object A Seurat object
#' @param known_tissue_type The tissue type of the input data (optional)
#' @param custom_marker_file Path to the custom marker file (optional)
#' @param plot Whether to plot the results (default is FALSE)
#' @param name The name of the metadata column to store the scType results (default is "sctype_classification")
#' @return A modified copy of the input Seurat object with a new metadata column
#' 
#' @import sctype source code
#' @import Seurat DimPlot
#' 
#' @examples
#' seurat_object=run_scType(seurat_object,"Immune system)
#' 
#' @export
#' 


run_sctype <- function(seurat_object, known_tissue_type = NULL, custom_marker_file = NULL, plot = FALSE, name = "sctype_classification") {
    db_=sctype_source()
    # Check for missing arguments
    if (is.null(seurat_object)) {
        stop("Argument 'seurat_object' is missing")
    }
    if (!inherits(seurat_object, "Seurat")) {
        stop("Argument 'seurat_object' must be a Seurat object")
    }
    # Set default custom marker file
    if (is.null(custom_marker_file)) {
        custom_marker_file = db_
    }
    # Auto-detect tissue type if not provided
    if (is.null(known_tissue_type)) {
        tissue_type = auto_detect_tissue_type(path_to_db_file = custom_marker_file, 
                                              seuratObject = seurat_object, 
                                              scaled = TRUE, assay = "RNA")
        rownames(tissue_type)=NULL
        tissue_type=tissue_type$tissue[1]
    } else {
        tissue_type = known_tissue_type
    }
    
    # Prepare gene sets
    gs_list = gene_sets_prepare(custom_marker_file, tissue_type)
    
    package_type=substr(packageVersion("Seurat"), 1, 1)
    
    if(package_type==5){
        print("Running with Seuratv5")
        es.max = sctype_score(scRNAseqData = seurat_object[["RNA"]]$scale.data,
                              scaled = TRUE,gs = gs_list$gs_positive, 
                              gs2 = gs_list$gs_negative)
    }
    else{
        # Calculate scType scores
        print("Running with Seuratv4")
        es.max = sctype_score(scRNAseqData = seurat_object[["RNA"]]@scale.data,
                              scaled = TRUE,gs = gs_list$gs_positive, 
                              gs2 = gs_list$gs_negative)
    }
    
    # Extract top cell types for each cluster
    cL_resutls = do.call("rbind", lapply(unique(seurat_object@meta.data$seurat_clusters), function(cl){
        es.max.cl = sort(rowSums(es.max[ ,rownames(seurat_object@meta.data[seurat_object@meta.data$seurat_clusters==cl, ])]), decreasing = !0)
        head(data.frame(cluster = cl, type = names(es.max.cl), scores = es.max.cl, ncells = sum(seurat_object@meta.data$seurat_clusters==cl)), 10)
    }))
    sctype_scores = cL_resutls %>% group_by(cluster) %>% top_n(n = 1, wt = scores)  
    # set low-confident (low ScType score) clusters to "unknown"
    sctype_scores$type[as.numeric(as.character(sctype_scores$scores)) < sctype_scores$ncells/4] = "Unknown"
    seurat_object_res=seurat_object
    seurat_object_res@meta.data[name] = ""
    for(j in unique(sctype_scores$cluster)){
        cl_type = sctype_scores[sctype_scores$cluster==j,]; 
        seurat_object_res@meta.data[seurat_object_res@meta.data$seurat_clusters == j,name] = as.character(cl_type$type[1])
    }
    if(plot){
        plot_ = DimPlot(seurat_object_res, reduction = "umap", group.by = name)   
        print(plot_)
    }
    text_=paste("New metadata added: ",name)
    print(text_)
    return(seurat_object_res)
}    
