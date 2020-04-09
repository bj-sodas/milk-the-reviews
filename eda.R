library(tidyverse)
library(tidytext)
library(text2vec)
library(widyr)
library(igraph)
library(ggraph)
library(stringdist)
set.seed(1234)
cnf = config::get()
old = theme_set(theme_minimal(base_family = "Noto Sans CJK SC"))

# Load Data ---------------------------------------------------------------


# url: https://item.jd.com/{productId}.html#comment
load_brand <- function(conf, brand) {
    
    rds = paste0(conf$dir, conf[[brand]], ".rds") 
    if (!file.exists(rds)) {
        return("File not found.")
    }
    tibble(comment = readRDS(rds)) %>% 
        rownames_to_column("id")
}
brands = list("nestle", "devon", "mengn")
raw <- brands %>% map(load_brand, conf = cnf) %>% set_names(brands)

# add custom stop words to list
custom_stops <- c(stopwords::stopwords("zh", source = "misc"), cnf$stop_words)

# the ICU library (used internally by the stringi package) is able to handle Chinese words
tidy_words <- . %>% 
    unnest_tokens(word, comment, token = "words") %>% 
    filter(!word %in% custom_stops) %>% 
    filter(!str_detect(word, "^\\d+$"))

# words collection
tidy <- map(raw, tidy_words) %>% set_names(brands)


# Word Frequency by Brand --------------------------------------------------------


# collect respective top words
count_top_words <- . %>% 
    count(word, sort = TRUE) %>% 
    top_n(30, wt = n)

top_words <- tidy %>% 
    map(count_top_words) %>% 
    set_names(brands) %>% 
    bind_rows(.id = "brand")

plot_top_words <- function(df, title) {
    df %>% 
        ggplot(aes(reorder(word, n), n)) + 
        geom_col(width = .3) +
        coord_flip() +
        labs(x = "", y = "", title = title)
}
top_words %>% subset(brand == "nestle") %>% plot_top_words("Most Freq Words in Nestle")
top_words %>% subset(brand == "devon") %>% plot_top_words("Most Freq Words in Devon")

# do compare 
top_words %>% 
    ggplot(aes(word, n, col = brand)) + 
    geom_line(aes(group = word), col = "gray") + 
    geom_point(size = 2) + 
    coord_flip() +
    theme(legend.position = "top") +
    labs(x = "", y = "", col = "Brand", title = "Count of Top Words by Brand")


# Network  ----------------------------------------------------------------


# network of common pairing words
make_graph <- . %>% 
    pairwise_count(word, id, sort = TRUE, upper = FALSE) %>%
    filter(n >= 30) %>% 
    graph_from_data_frame() 

plot_graph <- function(x) {
    ggraph(x, layout = "fr") +
        geom_edge_link(aes(edge_alpha = n),
                       edge_width = 2,
                       edge_colour = "navyblue",
                       show.legend = FALSE) +
        geom_node_point(size = 3, col = "darkblue") +
        geom_node_text(
            aes(label = name),
            repel = TRUE,
            family = "Noto Sans CJK SC",
            size = 3,
            point.padding = unit(0.2, "lines")
        ) +
        theme_void()
}
tidy$nestle %>% make_graph() %>% plot_graph()
tidy$devon  %>% make_graph() %>% plot_graph()
tidy$mengn  %>% make_graph() %>% plot_graph()


# Compare Differences -----------------------------------------------------

# between 2 brands only
tidy$nestle %>% 
    anti_join(tidy$devon, by = "word") %>% 
    count(word, sort = TRUE) %>% 
    top_n(10, wt = n)

tidy$devon %>% 
    anti_join(tidy$nestle, by = "word") %>% 
    count(word, sort = TRUE) %>% 
    top_n(10, wt = n)

# bind tf-idf
tf_idf <- tidy %>% 
    map(~ count(.x, word, sort = TRUE)) %>% 
    bind_rows(.id = "brand") %>% 
    bind_tf_idf(word, brand, n) %>% 
    arrange(desc(tf_idf))

# take note of ranking within facet
tf_idf %>% 
    group_by(brand) %>% 
    top_n(30, wt = tf_idf) %>% 
    ungroup() %>% 
    mutate(brand = factor(brand, ordered = TRUE, levels = brands)) %>% 
    ggplot(aes(reorder_within(word, tf_idf, brand), tf_idf, fill = brand)) + 
    geom_col(width = .3, show.legend = FALSE) +
    coord_flip() +
    scale_x_discrete(labels = function(x) gsub("__.+$", "", x)) +
    scale_fill_brewer(palette = "Dark2") +
    facet_wrap(~ brand, scales = "free") +
    labs(x = "", y = "")

# quantify dissimilarity
tf_idf_by_brand <- tf_idf %>% 
    group_by(brand) %>% 
    top_n(30, wt = tf_idf) %>% 
    ungroup() %>% 
    select(brand, word) %>% 
    split(.$brand, drop = TRUE)

jaccard <- function(x, y) {
    length(intersect(x, y)) / length(union(x, y))
}
# test
jaccard(tf_idf_by_brand$nestle$word, tf_idf_by_brand$devon$word)

# a scalable solution
xy_comb <- cross2(brands, brands, .filter = ~ .x == .y)
xy_name <- map_chr(xy_comb, ~ paste(.x[1], .x[2], sep = "-"))
map(xy_comb,
    ~ jaccard(tf_idf_by_brand[[.x[[1]]]]$word,
              tf_idf_by_brand[[.x[[2]]]]$word)) %>%
    set_names(xy_name)
