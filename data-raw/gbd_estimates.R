# Prep GBD 2019 VPD burden estimates
convert_single_year <- function(gbd_dt) {
    conv_table <- data.table(
        age = c(0, rep(1, 4), rep(seq(5, 75, 5), each = 5), rep(80, 16)),
        age_new = 0:95,
        n = c(1, rep(4, 4), rep(5, 75), rep(16, 16))
    )
    out_dt <- merge(gbd_dt, conv_table, by = "age", allow.cartesian = T)
    out_dt[, age := age_new]
    out_dt[, value := value / n]
    out_dt[, c("age_new", "n") := NULL]

    return(out_dt[])
}

## Load data
load(system.file("extdata", "gbd19_estimates.RData", package = "vieIA2030"))
gbd_estimates <- convert_single_year(gbd_estimates)
gbd_estimates <- gbd_estimates[
    order(location_id, disease, sex_id, age, year),
    .(location_id, disease, sex_id, age, year, value)
]
gbd_estimates <- merge(gbd_estimates, d_v_at_table, by = "disease")
upload_object(gbd_estimates, "gbd_strata_deaths")
