args <- commandArgs(trailingOnly = TRUE)
case_csv <- if (length(args) >= 1) args[[1]] else 'readiness_case_study_eval_log.csv'
out_dir  <- if (length(args) >= 2) args[[2]] else 'figures_out'
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

upper_cp <- function(x, n, alpha = 0.05) {
  if (n == 0) return(1)
  if (x >= n) return(1)
  if (x == 0) return(1 - alpha^(1 / n))
  qbeta(1 - alpha, x + 1, n - x)
}

simulate_one <- function(params, rule_name, alpha = 0.05, tau = 0.01, rho = 0.10,
                         rep_round = 25, target_round = 25, rounds = 60,
                         w = 100, fixed_round = 12, post_horizon = 200) {
  p <- unlist(params$p)
  H <- length(p)
  max_rep <- rep_round * rounds
  max_target <- target_round * rounds
  rep <- sapply(p, function(ph) rbinom(max_rep, 1, ph))
  if (is.vector(rep)) rep <- matrix(rep, nrow = max_rep, ncol = H)
  rep <- t(rep)

  q_target <- params$q_target
  severe <- rbinom(max_target + post_horizon, 1, q_target)
  J <- params$J
  s <- params$s
  weights <- (1:J)^(-s)
  weights <- weights / sum(weights)
  types <- rep(NA_integer_, max_target + post_horizon)
  sev_idx <- which(severe == 1)
  if (length(sev_idx) > 0) types[sev_idx] <- sample(0:(J - 1), length(sev_idx), replace = TRUE, prob = weights)

  seen <- rep(FALSE, J)
  counts <- rep(0L, J)
  new_indicator <- rep(0L, max_target)
  nerr_history <- rep(0L, max_target)
  mhat_history <- rep(1, max_target)
  true_missing_history <- rep(1, max_target)
  nerr <- 0L

  for (t in seq_len(max_target)) {
    if (severe[t] == 1) {
      j <- types[t] + 1L
      nerr <- nerr + 1L
      counts[j] <- counts[j] + 1L
      if (!seen[j]) {
        seen[j] <- TRUE
        new_indicator[t] <- 1L
      }
    }
    nerr_history[t] <- nerr
    mhat_history[t] <- if (nerr > 0) sum(counts == 1L) / nerr else 1
    true_missing_history[t] <- sum(weights[!seen])
  }

  stop_round <- NA_integer_
  rep_n <- max_rep
  targ_n <- max_target
  U <- rep(1, H)
  recent_novelty <- NA_real_
  nerr_now <- nerr_history[max_target]
  mhat <- mhat_history[max_target]
  true_missing <- true_missing_history[max_target]

  for (r in seq_len(rounds)) {
    rep_n <- rep_round * r
    targ_n <- target_round * r
    x <- rowSums(rep[, seq_len(rep_n), drop = FALSE])
    U <- mapply(upper_cp, x = x, n = rep_n, MoreArgs = list(alpha = alpha))
    rate_ok <- all(U <= tau)
    recent_novelty <- if (targ_n >= w) sum(new_indicator[(targ_n - w + 1):targ_n]) else NA_real_
    nerr_now <- nerr_history[targ_n]
    mhat <- mhat_history[targ_n]
    true_missing <- true_missing_history[targ_n]
    novelty_ok <- targ_n >= w && recent_novelty == 0
    gt_ok <- nerr_now >= 20 && mhat <= rho

    criterion <- switch(rule_name,
      fixed_budget = r >= fixed_round,
      rate_only = rate_ok,
      recent_novelty = novelty_ok && rep_n >= 300,
      dual_rule = rate_ok && novelty_ok && gt_ok,
      stop('unknown rule')
    )

    if (criterion) {
      stop_round <- r
      break
    }
  }

  seen_until_stop <- unique(types[seq_len(targ_n)][!is.na(types[seq_len(targ_n)])])
  future_types <- unique(types[(targ_n + 1):(targ_n + post_horizon)][!is.na(types[(targ_n + 1):(targ_n + post_horizon)])])
  missed_new <- length(setdiff(future_types, seen_until_stop))
  premature <- !is.na(stop_round) && (max(p) > tau || true_missing > rho)

  data.frame(
    stopped = !is.na(stop_round),
    stop_round = ifelse(is.na(stop_round), rounds + 1, stop_round),
    rep_n_per_slice = rep_n,
    target_n = targ_n,
    total_evals = rep_n * H + targ_n,
    max_U95 = max(U),
    max_true_p = max(p),
    recent_novelty = recent_novelty,
    N_err = nerr_now,
    Mhat = mhat,
    true_missing = true_missing,
    missed_new_types_200 = missed_new,
    premature_stop = premature,
    stringsAsFactors = FALSE
  )
}

run_simulation <- function(n_rep = 300, seed = 20260409) {
  set.seed(seed)
  scenarios <- list(
    safe_short_tail = list(p = c(0.0015, 0.0025, 0.0030, 0.0040), J = 12, s = 1.4, q_target = 0.25),
    safe_long_tail = list(p = c(0.0015, 0.0025, 0.0030, 0.0040), J = 60, s = 0.8, q_target = 0.25),
    near_threshold_long_tail = list(p = c(0.0050, 0.0060, 0.0070, 0.0080), J = 60, s = 0.8, q_target = 0.25),
    unsafe_long_tail = list(p = c(0.0100, 0.0120, 0.0140, 0.0150), J = 60, s = 0.8, q_target = 0.25)
  )
  rules <- c('fixed_budget', 'rate_only', 'recent_novelty', 'dual_rule')
  out <- list()
  k <- 1L
  for (scenario_name in names(scenarios)) {
    params <- scenarios[[scenario_name]]
    for (rule in rules) {
      for (i in seq_len(n_rep)) {
        row <- simulate_one(params, rule)
        row$scenario <- scenario_name
        row$rule <- rule
        row$replicate <- i
        out[[k]] <- row
        k <- k + 1L
      }
    }
  }
  do.call(rbind, out)
}

summarize_sim <- function(raw_df) {
  agg_mean <- function(x) mean(x, na.rm = TRUE)
  aggregate(cbind(stopped, rep_n_per_slice, target_n, total_evals, premature_stop,
                  missed_new_types_200, true_missing, Mhat, N_err, max_U95) ~ scenario + rule,
            data = transform(raw_df,
                             stopped = as.numeric(stopped),
                             premature_stop = as.numeric(premature_stop)),
            FUN = agg_mean)
}

plot_case_study <- function(case_csv, out_dir) {
  df <- read.csv(case_csv, stringsAsFactors = FALSE)
  rep_df <- subset(df, lane == 'representative')
  targ_df <- subset(df, lane == 'targeted')
  n <- 1:3000
  u <- 1 - 0.05^(1 / n)
  png(file.path(out_dir, 'figure1_rate_bound_case_study.png'), width = 1600, height = 1040, res = 200)
  plot(n, 100 * u, type = 'l', lwd = 2,
       xlab = 'Relevant evaluation opportunities, n',
       ylab = 'One-sided 95% upper bound (%)',
       main = 'Upper confidence bound for zero observed uncaught critical failures',
       ylim = c(0, 3.4))
  abline(h = c(1.0, 0.5, 0.1), lty = 2)
  text(c(300, 600, 3000), c(1.0, 0.5, 0.1) + c(0.1, 0.1, 0.05),
       labels = c('1.0% threshold', '0.5% threshold', '0.1% threshold'), pos = 4, cex = 0.8)
  slices <- split(rep_df, rep_df$slice)
  for (nm in names(slices)) {
    g <- slices[[nm]]
    nn <- sum(g$relevant)
    xx <- sum(g$uncaught == 1 & g$severity == 'critical')
    uu <- upper_cp(xx, nn)
    points(nn, 100 * uu, pch = 19)
    text(nn, 100 * uu, labels = gsub('_', ' ', nm), pos = 4, cex = 0.8)
  }
  dev.off()

  seen <- character(0)
  K <- integer(nrow(targ_df))
  new_pos <- integer(0)
  for (i in seq_len(nrow(targ_df))) {
    et <- targ_df$error_type[i]
    if (!is.na(et) && !(et %in% seen)) {
      seen <- c(seen, et)
      new_pos <- c(new_pos, i)
    }
    K[i] <- length(seen)
  }
  png(file.path(out_dir, 'figure2_case_study_discovery.png'), width = 1600, height = 1040, res = 200)
  plot(seq_along(K), K, type = 's', lwd = 2,
       xlab = 'Targeted evaluations',
       ylab = 'Cumulative distinct severe error types',
       main = 'Illustrative case study: severe-error discovery curve',
       ylim = c(0, max(K) + 1))
  abline(v = new_pos, lty = 3)
  dev.off()
}

plot_sim_summary <- function(summary_df, out_dir) {
  scenario_order <- c('safe_short_tail', 'safe_long_tail', 'near_threshold_long_tail', 'unsafe_long_tail')
  rule_order <- c('fixed_budget', 'recent_novelty', 'rate_only', 'dual_rule')
  scenario_labels <- c('Safe,\nshort tail', 'Safe,\nlong tail', 'Near-threshold,\nlong tail', 'Unsafe,\nlong tail')
  rule_labels <- c('Fixed budget', 'Recent novelty', 'Rate only', 'Dual rule')
  ord <- interaction(summary_df$scenario, summary_df$rule, drop = TRUE)

  get_mat <- function(col) {
    m <- matrix(NA_real_, nrow = length(rule_order), ncol = length(scenario_order))
    rownames(m) <- rule_order
    colnames(m) <- scenario_order
    for (sc in scenario_order) {
      for (ru in rule_order) {
        m[ru, sc] <- summary_df[summary_df$scenario == sc & summary_df$rule == ru, col]
      }
    }
    m
  }

  png(file.path(out_dir, 'figure3_sim_premature_stop.png'), width = 1800, height = 1080, res = 200)
  bp <- barplot(get_mat('premature_stop'), beside = TRUE, ylim = c(0, 1.05),
                names.arg = scenario_labels,
                main = 'Monte Carlo study: premature-stop risk by rule',
                ylab = 'Premature stop rate', las = 1)
  legend('topleft', legend = rule_labels, fill = seq_along(rule_labels), bty = 'n', cex = 0.9)
  dev.off()

  png(file.path(out_dir, 'figure4_sim_missed_novel.png'), width = 1800, height = 1080, res = 200)
  barplot(get_mat('missed_new_types_200'), beside = TRUE,
          names.arg = scenario_labels,
          main = 'Monte Carlo study: novel severe types missed after stopping',
          ylab = 'Mean novel severe types discovered in next 200 targeted tests', las = 1)
  legend('topright', legend = rule_labels, fill = seq_along(rule_labels), bty = 'n', cex = 0.9)
  dev.off()

  png(file.path(out_dir, 'figure5_sim_budget.png'), width = 1800, height = 1080, res = 200)
  barplot(get_mat('total_evals'), beside = TRUE,
          names.arg = scenario_labels,
          main = 'Monte Carlo study: evaluation budget consumed before stopping',
          ylab = 'Mean evaluations consumed', las = 1)
  legend('topleft', legend = rule_labels, fill = seq_along(rule_labels), bty = 'n', cex = 0.9)
  dev.off()
}

plot_case_study(case_csv, out_dir)
raw_df <- run_simulation(300, 20260409)
write.csv(raw_df, file.path(out_dir, 'simulation_raw.csv'), row.names = FALSE)
summary_df <- summarize_sim(raw_df)
write.csv(summary_df, file.path(out_dir, 'simulation_summary.csv'), row.names = FALSE)
plot_sim_summary(summary_df, out_dir)
