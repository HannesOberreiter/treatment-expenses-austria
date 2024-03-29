# Description -------------------------------------------------------------
# Cleanup of survey answers which must be wrong
# or not logical (e.g.more than possible)
# also code snippets for reporting on material and methods section
mmList <- list()

## Motivation -------------------------------------------------------------
dfMotivation <- dfData %>%
  filter(year == "20/21" & submitted == "Internet") %>%
  select(id, starts_with("motivation_"), state) %>%
  pivot_longer(starts_with("motivation_")) %>%
  drop_na(value) %>%
  left_join(motivationList, by = c("name" = "cname")) %>%
  add_count(id, value) %>%
  glimpse()
# Check how many did not answer this question
mmList$motivation$no_answer <- dfMotivation %>%
  count(id, value) %>%
  filter(value == "Nein" & n == 21) %>%
  arrange(desc(n))

# Remove the entries without any answer
dfMotivation <- dfMotivation %>% filter(!(id %in% mmList$motivation$no_answer$id))
# Count for M&M text
mmList$motivation$valid_answers <- length(unique(dfMotivation$id))

## Paper and Newspaper -----------------------------------------------------
# The expenses question is only in the internet
# version available, therefore we need to report how much we drop
mmList$submitted_year <- dfData %>%
  group_by(submitted, year) %>%
  summarise(n = n())
mmList$submitted_all <- dfData %>%
  group_by(submitted) %>%
  summarise(n = n())

# Internet but did not answer costs
mmList$internet_no_answer <- dfData %>%
  filter(submitted == "Internet") %>%
  mutate(answered = is.na(costs)) %>%
  dplyr::add_count(year) %>%
  group_by(year, answered) %>%
  summarise(
    nn = n(),
    np = round(nn / first(n) * 100, 1)
  ) %>%
  filter(answered == TRUE)

# Generate DATA -----------------------------------------------------------
# Extract only answers with valid answer for costs
dfClean <- dfData[!is.na(dfData$costs), ]
dfClean %>% count(submitted)

## No Treatment Answer but Costs -----------------------------------------------------
mmList$no_treatment <- dfClean %>%
  filter(varroa_treated != "Ja") %>%
  select(c("id", "costs", "varroa_treated", "comments", "year", "t_amount", "c_short"))
dfClean <- dfClean %>% filter(!(id %in% mmList$no_treatment$id))

## No Treatment Method given -----------------------------------------------
# Extract Participants which did answer costs but
# did give no answer on what treatment
mmList$no_method <- dfClean %>%
  filter(is.na(t_short)) %>%
  select(c("id", "costs", "varroa_treated", "comments", "year", "t_amount", "c_short", "hives_winter"))
dfClean <- dfClean %>% filter(!(id %in% mmList$no_method$id))

## Zero Costs ------------------------------------------------------------
mmList$cost_zero <- list()
mmList$cost_zero$data <- dfClean %>%
  filter(costs == 0) %>%
  select(c("id", "costs", "varroa_treated", "comments", "year", "t_amount", "c_short"))
# sponsorship (e.g. Imkereiförderung, Gemeinde)
mmList$cost_zero$id_sponsor <- c("353-18/19", "752-18/19", "855-18/19", "1624-18/19")
# biotechnical & hyperthermie
mmList$cost_zero$id_keep <- c("1750-18/19")
mmList$cost_zero$id_remove <- mmList$cost_zero$data %>%
  filter(!(id %in% mmList$cost_zero$id_keep)) %>%
  pull(id)
dfClean <- dfClean %>%
  filter(!(id %in% mmList$cost_zero$id_remove))

## Outliers / High Costs --------------------------------------------------------------
mmList$cost_upper <- list()
mmList$cost_upper$upper_limit <- (quantile(dfClean$costs, probs = 0.75, names = FALSE) + 3 * IQR(dfClean$costs)) * 2
mmList$cost_upper$data <- dfClean %>%
  filter(costs >= mmList$cost_upper$upper_limit) %>%
  select(c("id", "varroa_treated", "comments", "year", "t_amount", "c_short", "costs", "t_estimated", "hives_winter")) %>%
  mutate(
    new_cost = round(costs / hives_winter)
  )

# Anomaly Detection based on isolation forest method
# if we set output_score = TRUE is will overwrite smaple_size to use all rows
mmList$cost_upper$iso_ext <- isotree::isolation.forest(
  dfClean %>% select(costs, t_short_od_lump),
  seed = 1337,
  ndim = 2,
  # standardize_data = TRUE,
  nthreads = -1,
  ntrees = 10,
  recode_categ = TRUE,
  sample_size = 256,
  # prob_pick_pooled_gain = 0,
  # prob_pick_avg_gain = 0,
  missing_action = "fail"
)

dfClean$outlier_score <- predict(mmList$cost_upper$iso_ext, dfClean)

mmList$cost_upper$forest <- dfClean %>%
  filter(outlier_score >= 0.6) %>%
  select(c("id", "varroa_treated", "comments", "year", "t_amount", "c_short", "costs", "t_estimated", "hives_winter")) %>%
  mutate(
    new_cost = round(costs / hives_winter)
  )

# Scores should be around 0.5
p <- dfClean %>%
  mutate(hcolor = ifelse(outlier_score >= 0.6, colorBlindBlack8[8], "black")) %>%
  ggplot(
    aes(x = costs, y = outlier_score, color = hcolor)
  ) +
  annotate("rect", xmin = -Inf, xmax = Inf, ymin = 0.6, ymax = Inf, alpha = 0.4, fill = colorBlindBlack8[7]) +
  geom_point() +
  ggplot2::scale_color_identity(guide = "legend", labels = c("Anomaly\n(>=0.6)\n", "Average\n(< 0.6)\n")) +
  ylim(0, 1) +
  labs(color = "") +
  xlab("Expenses per colony") +
  ylab("Standardized outlier score") +
  ggplot2::theme(
    panel.grid.major = element_line()
  )

fSaveImages(p, "isolation_forest")

print("extreme IQR:")
nrow(mmList$cost_upper$data)
print("isolation Forest:")
nrow(mmList$cost_upper$forest)
print("Overlapping:")
nrow(inner_join(mmList$cost_upper$forest, mmList$cost_upper$data))
# Combine the two lists
mmList$cost_upper$combined_list <- bind_rows(mmList$cost_upper$forest, mmList$cost_upper$data) %>%
  distinct(id, .keep_all = TRUE)

# Remove these entries, as they make sense
# Remove participants which used hyperthermia as we can make no assumptions about investement time
# 815-18/19 explains that he bought a power generator and vaporizer (not anymore inside our new limit, so he wont be changed anyway)
mmList$cost_upper$id_nochange <- c("815-18/19")
mmList$cost_upper$new_data <- mmList$cost_upper$combined_list %>%
  filter(!(id %in% mmList$cost_upper$id_nochange | stringr::str_detect(c_short, "Hyp.")))

# add new calculated costs to our main df
dfClean$costs[(dfClean$id %in% mmList$cost_upper$new_data$id)] <- mmList$cost_upper$new_data$new_cost

# create plot which shows the differnce
p1 <- patchwork::wrap_plots(
  A = mmList$cost_upper$new_data %>%
    ggplot2::ggplot() +
    aes(x = hives_winter, y = costs) +
    geom_point() +
    xlab("Number of colonies [#]") +
    ylab("Reported Expenses/Colony [EUR]") +
    ggplot2::scale_x_continuous(
      breaks = scales::breaks_width(100),
    ) +
    ggplot2::scale_y_continuous(
      breaks = scales::breaks_width(100),
      limits = c(0, 550)
    ) +
    ggplot2::theme(
      panel.grid.major = element_line()
    ) +
    ggplot2::coord_equal(),
  B = mmList$cost_upper$new_data %>%
    ggplot2::ggplot() +
    aes(x = hives_winter, y = new_cost) +
    geom_point() +
    xlab("Number of colonies [#]") +
    ylab("Manipulated Expenses/Colony [EUR]") +
    ggplot2::scale_x_continuous(
      breaks = scales::breaks_width(100),
    ) +
    ggplot2::scale_y_continuous(
      breaks = scales::breaks_width(100),
      limits = c(0, 550)
    ) +
    ggplot2::theme(
      panel.grid.major = element_line()
    ) +
    ggplot2::coord_equal()
) + plot_annotation(tag_levels = c("A", "1"))

fSaveImages(p1, "manipulated-costs", h = 7, w = 8)


## Difference --------------------------------------------------------------
mmList$reports <- dfData %>%
  count(year, name = "survey_n") %>%
  left_join(
    dfClean %>% count(year, name = "valid_n")
  ) %>%
  mutate(
    percent = round(valid_n / survey_n * 100)
  )

## Count Uncertain and No Answers for Single Factor Analyses --------------------------------------------------------------

mmList$single_factor_drop <- bind_rows(
  dfClean %>%
    filter(is.na(op_cert_org_beek) | op_cert_org_beek == "Unsicher") %>%
    count(year, op_cert_org_beek) %>%
    pivot_longer(op_cert_org_beek) %>%
    mutate(
      name = "Certified Organic Beekeeper",
      value = stringr::str_replace_na(value, "No Answer") %>% str_replace("Unsicher", "Uncertain")
    ),
  dfClean %>%
    filter(is.na(op_migratory_beekeeper) | op_migratory_beekeeper == "Unsicher") %>%
    count(year, op_migratory_beekeeper) %>%
    pivot_longer(op_migratory_beekeeper) %>%
    mutate(
      name = "Migratory Beekeeper",
      value = stringr::str_replace_na(value, "No Answer") %>% str_replace("Unsicher", "Uncertain")
    )
)
