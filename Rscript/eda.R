library(tidyverse)
library(tidytext)
library(text2vec)
library(widyr)
library(igraph)
library(ggraph)
library(stringdist)

# global
set.seed(1234)
cnf    = config::get()
pref   = config::get(config = "pref")
old    = theme_set(theme_minimal(base_family = "Noto Sans CJK SC"))
brands = names(cnf)

# define color palette
pal = list(
    "nestle" = pref$nestle.col,
    "devon"  = pref$devon.col,
    "maxig"  = pref$maxig.col,
    "anchr"  = pref$anchr.col
)

# Load Data ---------------------------------------------------------------


# url: https://item.jd.com/{productId}.html#comment
load_brand <- function(brand, conf) {
    
    rds = paste0(conf$dir, conf[[brand]], ".rds") 
    if (!file.exists(rds)) {
        return("File not found.")
    }
    tibble(comment = readRDS(rds)) %>% 
        rownames_to_column("id")
}

raw <- names(cnf) %>% 
    map(paste0, ".id") %>% 
    map(~ load_brand(.x, pref)) %>% 
    set_names(brands)

# add custom stop words to list
custom_stops <- c(stopwords::stopwords("zh", source = "misc"), read_lines("custom_stops.txt"))

# the ICU library (used internally by the stringi package) is able to handle Chinese words
tidy_words <- . %>% 
    unnest_tokens(word, comment, token = "words") %>% 
    filter(!word %in% custom_stops) %>% 
    filter(!str_detect(word, "^\\d+(\\W{1}\\d+)?$|[a-z]+"))

# words collection
tidy <- map(raw, tidy_words) %>% set_names(brands)


# Word Frequency by Brand --------------------------------------------------------


# collect respective top words
count_top_words <- . %>% 
    count(word, sort = TRUE) %>% 
    top_n(15, wt = n) %>% 
    pull(word)

# compare across brands
top_words <- tidy %>% map(count_top_words) %>% unlist()
    
tidy %>% 
    bind_rows(.id = "brand") %>% 
    filter(word %in% top_words) %>% 
    count(brand, word, sort = TRUE) %>% 
    mutate(brand = factor(brand, ordered = TRUE, levels = brands)) %>% 
    ggplot(aes(reorder(word, n), n, col = brand)) + 
    geom_line(aes(group = word), col = "gray") + 
    geom_point(size = 3) + 
    scale_y_continuous(limits = c(0, 500)) +
    scale_color_manual(labels = as_vector(cnf), values = pal) +
    coord_flip() +
    theme(legend.position = "top") +
    labs(x = "", y = "", col = "", title = "Top Words Count by Brand")


# Sentence Length Distribution --------------------------------------------


n_chars <- map(raw, ~ nchar(.x$comment)) %>% 
    as.data.frame() %>% 
    gather(brand, nchar) %>% 
    as_tibble()

n_chars %>% 
    filter(nchar < 300) %>% 
    mutate(brand = factor(brand, ordered = TRUE, levels = brands)) %>% 
    ggplot(aes(nchar, fill = brand)) + 
    geom_histogram(
        bins = 150,
        alpha = .7,
        show.legend = FALSE,
        col = "white"
    ) +
    scale_x_continuous(breaks = seq(0, 300, 50)) +
    scale_fill_manual(values = pal) +
    facet_wrap(~ brand, ncol = 1,
               labeller = labeller(brand = as_vector(cnf))) +
    labs(x = "", y = "")


# Network  ----------------------------------------------------------------


# network of common pairing words
plot_graph <- function(df, term_min, edge = n) {
    
    e = enquo(edge)
    
    # beware of 2 layers of filtering
    g <- df %>%
        filter(!word %in% c("奶")) %>%
        pairwise_count(word, id, sort = TRUE, upper = FALSE) %>%
        filter(n > term_min) %>%
        graph_from_data_frame()
    
    g %>%
        ggraph(layout = "fr") +
        geom_edge_link(
            aes(edge_alpha = rlang::as_name(e)),
            edge_width = 2,
            edge_colour = "navyblue",
            show.legend = FALSE
        ) +
        geom_node_point(size = 3, col = "darkblue") +
        geom_node_text(
            aes(label = name),
            repel = TRUE,
            family = "Noto Sans CJK SC",
            size = 5,
            point.padding = unit(0.2, "lines")
        ) +
        theme_void()
}

set.seed(1234)
plot_graph(tidy$nestle, 10)
plot_graph(tidy$devon,  25)
plot_graph(tidy$maxig,  25)
plot_graph(tidy$anchr,  25)

# Compare Differences -----------------------------------------------------

# between 2 brands only
tidy$nestle %>% 
    anti_join(tidy$devon, by = "word") %>% 
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
    top_n(25, wt = tf_idf) %>% 
    ungroup() %>% 
    mutate(brand = factor(brand, ordered = TRUE, levels = brands)) %>% 
    ggplot(aes(reorder_within(word, tf_idf, brand), tf_idf, fill = brand)) + 
    geom_col(width = .3, show.legend = FALSE) +
    coord_flip() +
    scale_x_discrete(labels = function(x) gsub("__.+$", "", x)) +
    scale_fill_manual(values = pal) +
    facet_wrap(~ brand, scales = "free_y", labeller = labeller(brand = as_vector(cnf))) +
    labs(x = "", y = "")

# for Maxigenes case
x <- tidy$anchr %>% filter(word == "手感") %>% pull(id)
raw$anchr[unique(x),]

# quantify dissimilarity
tf_idf_by_brand <- tf_idf %>% 
    filter(tf_idf > 0.00001) %>%
    select(brand, word) %>% 
    # filter(!str_detect(word, "一")) %>% 
    split(.$brand, drop = TRUE)

jaccard <- function(x, y) {
    length(intersect(x, y)) / length(union(x, y))
}
# test
jaccard(tf_idf_by_brand$nestle$word, tf_idf_by_brand$anchr$word)

# a scalable solution
xy_comb <- cross2(brands, brands, .filter = ~ .x == .y)
xy_name <- map_chr(xy_comb, ~ paste(.x[1], .x[2], sep = "-"))
map(xy_comb,
    ~ jaccard(tf_idf_by_brand[[.x[[1]]]]$word,
              tf_idf_by_brand[[.x[[2]]]]$word)) %>%
    set_names(xy_name)


# Network TF-IDF ----------------------------------------------------------

tf_idf_graph <- function(brand, term_min) {
    tidy %>% 
        `[[`(brand) %>% 
        filter(word %in% tf_idf_by_brand[[brand]]$word) %>% 
        plot_graph(term_min = term_min)
}
set.seed(1234)
tf_idf_graph("nestle", 1)
tf_idf_graph("devon",  2)
tf_idf_graph("maxig",  2)
tf_idf_graph("anchr",  2)


