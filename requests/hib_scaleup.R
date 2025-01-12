
## Pull coverage
devtools::load_all()
load_tables("coverage")
cov_dt <- coverage[strata_id %in% c(5, 20) & age == 0 & year < 2020]
dt <- merge(cov_dt, strata_table[, .(strata_id, vaccine)])
cast_dt <- dcast(dt, location_id + year ~ vaccine, value.var = "coverage")
cast_dt[is.na(Hib3), Hib3 := 0]

## Hib to DTP3 ratio by year post Hib intro
intro_locs <- unique(cast_dt[Hib3 == 0]$location_id)
pos_dt <- cast_dt[(Hib3 > 0 & DTP3 > 0) & location_id %in% intro_locs]
pos_dt[, hib_intro := min(year), by = location_id]
pos_dt[, years_intro := year - hib_intro + 1]
pos_dt[, ratio := Hib3 / DTP3]

in_locs <- unique(pos_dt[Hib3 > 0 & year == 2019]$location_id)
out_locs <- setdiff(loc_table$location_id, in_locs)
loc_table[location_id %in% out_locs]$location_name
## Plot
pdf("plots/hib_scaleup_data.pdf")
gg <- ggplot(pos_dt, aes(x = years_intro, y = ratio, group = location_id)) +
  geom_line(alpha = 0.4) + theme_bw() + xlab("Years post Hib introduction") +
  ylab("Ratio of Hib to DTP3 coverage")
print(gg)
dev.off()

## Fit exponential model
model_dt <- pos_dt[years_intro <= 5]
model_dt[, x := years_intro / 5]
obj_fn <- function(alpha, dt) {
  pred <- dt$x^alpha
  stat <- mean((dt$ratio - pred)**2)
  return(stat)
}
fit <- optimize(obj_fn, 0:1, dt = model_dt[x < 1])
opt_val <- fit$objective

## Plot
pdf("plots/hib_scaleup_fit.pdf")
plot(jitter(model_dt$x * 5, 1), model_dt$ratio, pch = 20, xlim = c(0, 5),
     col=alpha(rgb(0,0,0), 0.5), xlab = "Years after Hib introduction",
     ylab = "Ratio of Hib to DTP3 coverage")
x <- seq(0, 1, 0.005)
lines(5 * x, x^opt_val, col = "red")
abline(h = 1, lty = "dashed")
dev.off()

## Scale-up Table
print(data.table(year = 1:5, hib_dtp3_ratio = (1:5 / 5)**opt_val))

## Summary statistics
print(summary_dt <- pos_dt[, .(median_ratio = median(ratio), mean_ratio = mean(ratio)), by = years_intro])
