## Make into Standalone Shiny Gadget for Tuning

# iterators
it <- itoken(word_tokenizer(txt), ids = 1:length(txt), progressbar = FALSE)

# vocabulary
vocabs <- it %>% 
    create_vocabulary(ngram = c(2, 3)) %>% 
    prune_vocabulary(doc_proportion_max = 0.1, term_count_min = 5)

# document-term matrix
dtm <- create_dtm(it, vocab_vectorizer(vocabs), type = "dgTMatrix")

# topic model
fit <- LDA$new(n_topics = 4, doc_topic_prior = 0.1, topic_word_prior = 0.01)
doc_topic_distr <- 
    fit$fit_transform(
        x = dtm,
        n_iter = 1000,
        convergence_tol = 0.001,
        n_check_convergence = 25,
        progressbar = FALSE
    )

# viz
fit$plot()