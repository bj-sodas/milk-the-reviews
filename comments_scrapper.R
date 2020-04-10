library(tidyverse)
library(httr)
library(jsonlite)
library(progress)

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

scrape_comments <- function(id, pages) {
    
    urls = map(1:pages, ~ form_url(id, .x))
    pb   = progress_bar$new(total = length(urls))
    
    resp = map(urls, ~ {
        pb$tick()
        fetch_data(.x)
    })
    
    unlist(resp)
}

raw <- scrape_comments(2087536, 50)

txt <- raw %>% 
    # remove html unicodes
    str_remove_all("&hellip;|&acute;|&forall;|&mdash;|\\\n") %>% 
    # remove non-word and whitespace
    str_remove_all("\\W|\\s")

