
CREATE OR REPLACE VIEW public.promo_n_plus_x_revision_grouped_vw AS (
WITH promo_condition_sales_with_bonus AS (
SELECT pcs.*, fpnpx.bonus, fpnpx.bonus * floor(pcs.sales_quantity / multiple) AS sum_bonus
FROM public.promo_condition_sales_vw pcs
JOIN (SELECT ds.id_common_sku, fpnpx.bonus, fpnpx.sale_date, fpnpx.id_client, fpnpx.delete_date FROM dwh.fct_promo_n_plus_x fpnpx JOIN dwh.dim_sku ds ON ds.id_sku = fpnpx.id_sku AND ds.delete_date IS NULL) as fpnpx
ON fpnpx.sale_date = pcs.start_date AND fpnpx.id_client = pcs.id_client and fpnpx.id_common_sku = pcs.id_common_sku AND fpnpx.delete_date IS null
),
grouped_by_client_and_day_promo_condition_sales_with_bonus AS (
SELECT id_common_sku, id_client, START_date, end_date, multiple, bonus, sum(sales_quantity) AS quantity, sum(sum_bonus) AS sum_bonus
FROM promo_condition_sales_with_bonus
GROUP BY id_common_sku, id_client, START_date, end_date, bonus, multiple
),
grouped_promo_results AS (
SELECT ds.id_common_sku, id_client, start_date, end_date, multiple, bonus,
sum(quantity) AS quantity_promo, sum(quantity) * bonus AS sum_bonus
FROM public.fct_promo_n_plus_x_result fpnpxr 
JOIN dwh.dim_sku ds ON ds.delete_date IS NULL AND fpnpxr.id_sku = ds.id_sku 
GROUP BY ds.id_common_sku, id_client, start_date, end_date, multiple, bonus
)
SELECT 
    gss.id_common_sku,
    gss.id_client,
    gss.start_date,
    gss.end_date,
    gss.multiple AS sales_multiple,
    gss.bonus AS sales_bonus,
    gss.quantity AS quantity_sales,
    gpr.quantity_promo,
    gpr.multiple AS promo_multiple,
    gpr.bonus AS promo_bonus,
    gss.sum_bonus AS sales_sum_bonus
FROM grouped_by_client_and_day_promo_condition_sales_with_bonus gss
LEFT JOIN grouped_promo_results gpr
ON gss.id_common_sku = gpr.id_common_sku
AND gss.id_client = gpr.id_client
AND gss.start_date =  gpr.start_date AND gss.end_date = gpr.end_date
--WHERE gpr.id_common_sku IS NOT NULL -- Раскомментировать, если нужно показать сверки только по тем акциям, для которых загружены результаты
)
