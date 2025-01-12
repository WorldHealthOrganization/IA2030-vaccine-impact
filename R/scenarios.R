gen_ia2030_goals <- function(ia2030_dtp_goal, linear = T,
                             no_covid_effect = 2022, intro_year = 2025,
                             intro_range = T) {
    # Load 2019 coverage
    load_tables("coverage")
    cov_dt <- coverage[year == 2019]

    # Iterate through each vaccine (except HPV which is special)
    vaccs <- setdiff(unique(v_at_table[activity_type == "routine"]$v_at_id), 2)
    dt <- rbindlist(lapply(vaccs, function(v) {
        v_dt <- cov_dt[v_at_id == v][order(location_id)]
        if (length(unique(v_dt$sex_id)) > 1) {
            v_dt <- v_dt[sex_id == 2]
        }
        missing_locs <- setdiff(loc_table$location_id, v_dt$location_id)
        missing_dt <- data.table(location_id = missing_locs, coverage = 0,
            v_at_id = v, year = 2019, age = 0, sex_id = unique(v_dt$sex_id),
            fvps = 0)
        v_dt <- rbind(v_dt, missing_dt, use.names = T)
        v_dt <- v_dt[order(location_id)]
        # Repeat out to 'no covid effect' year
        n_covid <- no_covid_effect - 2019
        covid_mat <- matrix(rep(v_dt$coverage, n_covid), ncol = n_covid)
        
        # Increase to goal with zeros delayed to intro_year
        n_increase <- 2030 - no_covid_effect + 1
        zero_idx <- which(v_dt$coverage == 0)
        # Change intro_year to 2024 for YF
        if (v == 19) {
            temp_intro_year <- intro_year - 1
        } else {
            temp_intro_year <- intro_year
        }
        if (intro_range) {
            # Range of intro years split up by quintile of coverage goal
            zero_locs <- v_dt[zero_idx]$location_id
            ordered_locs <- ia2030_dtp_goal[location_id %in% zero_locs][rev(order(value))]$location_id
            split_locs <- split(ordered_locs, floor(5 * seq.int(0, length(ordered_locs) - 1) / length(ordered_locs)))
            names(split_locs) <- (-2:2 + temp_intro_year)[1:length(split_locs)]
        } else {
            zero_n <- 2030 - temp_intro_year + 1
        }

        setnames(v_dt, "coverage", "current")
        roc_dt <- merge(
            v_dt[, .(location_id, current)],
            ia2030_dtp_goal[, .(location_id, value)],
            by = "location_id"
        )
        roc_dt[, n := n_increase]
        t_mat <- matrix(
            1:n_increase, byrow = T, ncol = n_increase, 
            nrow = nrow(roc_dt)
        )
        if (length(zero_idx > 0)) {
            if (intro_range) {
                for (i in zero_idx) {
                    i_year <- as.integer(names(split_locs)[unlist(
                        lapply(split_locs, function(s) {
                            v_dt[i,]$location_id %in% s
                        })
                    )])
                    zero_n <- 2030 - i_year + 1
                    t_mat[i, ] <- c(rep(0, n_increase - zero_n), 1:zero_n)
                    roc_dt[i, n := zero_n]
                }
            } else {
                t_mat[zero_idx,] <- matrix(
                    c(rep(0, n_increase - zero_n), 1:zero_n),
                    nrow = length(zero_idx), ncol = n_increase, byrow = T)
                roc_dt[zero_idx, n := zero_n]
            }
        }
        # Handle regionally-specific vaccines
        if (v %in% c(19, 12, 7)) {
            if (v == 19) {
                reg_locs <- loc_table[yf == 1]$location_id
                # Remove Argentina and Kenya
                reg_locs <- setdiff(reg_locs, c(7, 90))
            } else if (v == 12){
                reg_locs <- loc_table[mena == 1]$location_id
            } else if (v == 7) {
                reg_locs <- loc_table[je == 1]$location_id
                # Remove Russia and Pakistan
                reg_locs <- setdiff(reg_locs, c(131, 144))
            }
            reg_idx <- which(v_dt$location_id %in% reg_locs)
            roc_dt[!reg_idx, value := current]
        }
        # Do no introduce HepB or BCG in any countries
        if (v %in% c(3, 21)) {
            roc_dt[zero_idx, value := current]
        }
        # Hold medium/low BCG coverage constant in France, Ireland, Sweden
        if (v == 21) {
            hold_locs <- c(63, 83, 168)
            hold_idx <- which(v_dt$location_id %in% hold_locs)
            roc_dt[hold_idx, value := current]
        }
        # Keep current JE levels in countries with only subnational endemicity
        # Indonesia, India, and Malaysia
        if (v == 7) {
            hold_locs <- c(79, 80, 104)
            hold_idx <- which(v_dt$location_id %in% hold_locs)
            roc_dt[hold_idx, value := current]
        }
        # Linear vs. non-linear
        if (linear) {
            roc_dt[, roc := ((value - current) / n)]
            roc_dt[roc < 0, roc := 0]
            inc_mat <- v_dt$current + roc_dt$roc * t_mat
        } else {
            roc_dt[, roc := log((1 - value) /(1 - current)) /  n]
            roc_dt[roc > 0, roc := 0]
            inc_mat <- 1 - (1 - v_dt$current) * exp(roc_dt$roc * t_mat)
        }
        # Combine and convert to data.table
        c_mat <- cbind(covid_mat, inc_mat)
        colnames(c_mat) <- 2019:2030
        # matplot(t(c_mat), type = "l")
        dt <- cbind(v_dt[, -c("year", "current", "fvps"), with = F], c_mat)
        melt_dt <- melt(dt,
            id.vars = c("location_id", "v_at_id", "age", "sex_id"),
            variable.name = "year"
        )
        return(melt_dt)
    }))

    ## Add HPV
    dt <- rbind(dt, hpv_target, use.names = T)
    
    dt[, year := as.integer(as.character(year))]
    dt <- dt[year > 2019]
    return(dt)
}


get_mx_scen <- function(is, y0, y1, scen, mx, nx) {
    default_coverage <- get_scen_coverage(is, y0, y1, "Default") %>%
        rename(default_cov = coverage)
    scen_coverage <- get_scen_coverage(is, y0, y1, scen) %>%
        rename(scen_cov = coverage)
    deaths <- mx * nx

    ## VIMC
    vimc_deaths_change <- get_vimc_deaths_change(is, y0, y1, default_coverage,
        scen_coverage, mx)

    ## DTP
    # Calculate relative risk given coverage and scale deaths accordingly
    dtp_deaths_change <- NULL

    ## BCG
    bcg_deaths_change <- NULL

    scen_deaths <- deaths + vimc_deaths_change + dtp_deaths_change +
        bcg_deaths_change

    mx <- scen_deaths / nx

    return(mx)
}

get_scen_fvps <- function() {
    ## Merge on coverage scenario onto past for full set of FVPs
    past_dt <- coverage[year < 2020 & year >= 2000]
    setnames(past_dt, "coverage", "value")
    future_dt <- gen_ia2030_goals(ia2030_dtp_goal, linear = F, no_covid_effect = 2022, 
        intro_year = 2025, intro_range = T)
    fvp_future <- cov2fvp(future_dt)
    scenario_dt <- rbind(past_dt, fvp_future)

    return(scenario_dt)
}

get_vimc_deaths_change <- function(is, y0, y1, default_coverage, scen_coverage,
    mx) {
    vimc_deaths_change <- vimc_impact %>%
        filter(location_name == is & year %in% y0:y1) %>%
        left_join(default_coverage, by = c("year", "vaccine_id")) %>%
        left_join(scen_coverage, by = c("year", "vaccine_id")) %>%
        mutate(scalar = (default_cov - scen_cov) / default_cov) %>%
        mutate(deaths_change = scalar * value) %>%
        group_by(year, age) %>%
        summarise(deaths_change = sum(deaths_change, na.rm = T)) %>%
        ungroup() %>%
        tidyr::spread(year, deaths_change) %>%
        select(-c(age)) %>%
        as.matrix()
    # Fill in older age groups TODO: fix this on vimc_impact side
    vimc_deaths_change <- rbind(
        vimc_deaths_change,
        matrix(
            nrow = dim(mx)[1] / 2 - dim(vimc_deaths_change)[1],
            ncol = dim(mx)[2]
        )
    )
    # Split evenly across sexes
    vimc_deaths_change <- rbind(
        vimc_deaths_change / 2,
        vimc_deaths_change / 2
    )

    return(vimc_deaths_change)
}

get_deaths_scen <- function(deaths_obs, averted_obs, averted_scen) {
    deaths_scen <- deaths_obs + sum(averted_obs) - sum(averted_scen)

    return(deaths_scen)
}