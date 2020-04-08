library(tidyverse)
library(httr)
library(jsonlite)
library(text2vec)

# from JD.com
form_url <- function(productId, pageX) {
    str_glue(
        "https://club.jd.com/comment/productPageComments.action?\\
             callback=fetchJSON_comment98&\\
             productId={productId}&\\
             score=0&\\
             sortType=5&\\
             page={pageX}&\\
             pageSize=10"
    )
}

fetch_data <- function(url, delay = 1) {
    
    Sys.sleep(jitter(delay)) # pause
    
    url %>% 
        httr::GET() %>% 
        content(as = "text") %>% 
        str_remove("^fetchJSON_comment98.?") %>% 
        str_remove(".{2}$") %>% 
        jsonlite::fromJSON() %>% 
        pluck("comments", "content")
}

# raw <- map(1:50, ~ fetch_data(form_url(1522584, .x))) %>% unlist()

txt <- raw %>% 
    # remove html unicodes
    str_remove_all("&hellip;|&acute;|&forall;|&mdash;|\\\n") %>% 
    # remove non-word and whitespace
    str_remove_all("\\W|\\s")

