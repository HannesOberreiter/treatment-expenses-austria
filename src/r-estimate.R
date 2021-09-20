# Chapter Estimates Expenses VS actual Survey -------------------------------------------------------------------
r_estimate <- list()

# Table Comparison -------------------------------------------------------------------
r_estimate$table <- dfClean %>%
    group_by(year) %>%
    summarise(
        Survey_min = min(costs),
        Survey_mean = mean(costs),
        Survey_median = median(costs),
        Survey_max = max(costs),
        Estimate_min = min(t_estimated),
        Estimate_mean = mean(t_estimated),
        Estimate_median = median(t_estimated),
        Estimate_max = max(t_estimated)
    ) %>%
    mutate(
        dplyr::across(-year, ~ format(round(.x, 1), nsmall = 1)),
        year = paste0("20", year)
    ) %>%
    tidyr::pivot_longer(-year) %>%
    tidyr::separate(name, into = c("type", "method"), sep = "_") %>%
    tidyr::pivot_wider(names_from = method, values_from = value) %>%
    arrange(type) %>%
    glimpse()

# Bland-Altmann plot variant to check difference and between survey and estimate for treatment methods -------------------------------------------------------------------
r_estimate$data <- dfClean %>%
    group_by(c_short_od) %>%
    summarise(
        n = n(),
        p = round(n * 100 / nrow(dfClean), 1),
        m_survey = round(mean(costs), 2),
        med_survey = round(median(costs), 2),
        m_estimate = round(mean(t_estimated), 2),
        med_estimate = round(median(t_estimated), 2),
        log_survey = round(mean(log2(costs)), 2),
        log_estimate = round(mean(log2(t_estimated)), 2)
    ) %>%
    mutate(
        # log 2 transformation
        # 1 is double difference
        # -1 is half difference
        log_dif = log_survey - log_estimate
    ) %>%
    filter(n >= 10) %>%
    arrange(desc(n)) %>%
    glimpse()

## BlandAltmanLeh -------------------------------------------------------------------
r_estimate$ba <- BlandAltmanLeh::bland.altman.stats(r_estimate$data$log_survey, r_estimate$data$log_estimate)
r_estimate$ba
r_estimate$ba$label <- r_estimate$data$c_short_od

## Plot --------------------------------------------------------------------
limit_y <- round(
    ifelse(
        max(r_estimate$ba$diffs) > (-1 * min(r_estimate$ba$diffs)),
        max(r_estimate$ba$diffs),
        -1 * min(r_estimate$ba$diffs)
    ),
    digits = 1
) + 0.2

labellogi <- (r_estimate$ba$diffs < r_estimate$ba$lower.limit) |
    (r_estimate$ba$diffs > r_estimate$ba$upper.limit)
colorlogi <- ifelse(labellogi, colorBlindBlack8[8], colorBlindBlack8[1])

p <- ggplot() +
    aes(x = 2^(r_estimate$ba$means), y = r_estimate$ba$diffs) +
    geom_abline(
        aes(
            intercept = r_estimate$ba$lines,
            colour = I(c(colorBlindBlack8[3], colorBlindBlack8[5], colorBlindBlack8[3])),
            slope = c(rep(0, 3))
        ),
        show.legend = F
    ) +
    geom_abline(
        aes(
            intercept = r_estimate$ba$CI.lines,
            color = I(c(rep(colorBlindBlack8[3], 2), rep(colorBlindBlack8[5], 2), rep(colorBlindBlack8[3], 2))),
            slope = c(rep(0, 6))
        ),
        linetype = "dashed",
        alpha = 0.5,
        show.legend = FALSE
    ) +
    geom_hline(yintercept = 0, linetype = "dotted") +
    geom_point(
        aes(size = r_estimate$data$n, color = I(colorlogi)),
        show.legend = TRUE
    ) +
    ggrepel::geom_label_repel(
        aes(
            x = 2^r_estimate$ba$means[labellogi],
            y = r_estimate$ba$diffs[labellogi],
            label = r_estimate$ba$label[labellogi]
        ),
        size = 2
    ) +
    xlab("Mean of Survey and Estimates [Euro]") +
    ylab(TeX("Differences (Survey-Estimate) \\[$\\log_2$ Euro\\]")) +
    labs(size = "Combination [n]") +
    scale_y_continuous(limits = c(-1 * limit_y, limit_y), breaks = seq(-10, 10, 0.5)) +
    scale_x_continuous(limits = c(0, NA), breaks = seq(0, 100, 2))

fSaveImages(p, "bland-altman", h = 4.5)
rm(limit_y, labellogi, colorlogi, p)