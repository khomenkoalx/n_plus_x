CREATE MATERIALIZED VIEW promo_sales_with_total_mv AS
WITH promo_base_info AS (
  SELECT  
    lpcs.id_promotion, 
    fp.id_promotion_type, 
    lpcs.id_common_sku, 
    fp.id_client, 
    fp.start_date, 
    fp.end_date
  FROM dwh.lnk_promo_common_sku lpcs 
  JOIN dwh.fct_promotion fp USING(id_promotion)
  WHERE lpcs.delete_date IS NULL 
    AND fp.delete_date IS NULL
),
-- Основные продажи (с исключениями)
promo_condition_sales AS (
  SELECT 
    fss.*,
    sku.id_common_sku,
    pbi.id_promotion,
    pbi.id_promotion_type,
    pbi.start_date,
    pbi.end_date,
    CASE 
      WHEN fss.operation_date BETWEEN pbi.start_date AND pbi.end_date THEN 'promo'
      WHEN fss.operation_date BETWEEN pbi.start_date - (pbi.end_date - pbi.start_date) AND pbi.start_date-1 THEN 'control'
      ELSE NULL
    END AS sales_type
  FROM dwh.fct_sale_second fss
  JOIN dwh.dim_sku sku ON fss.id_sku = sku.id_sku
  RIGHT JOIN promo_base_info pbi ON 
    sku.id_common_sku = pbi.id_common_sku AND
    fss.id_client = pbi.id_client
  LEFT JOIN (
    -- Делаем подзапрос, где получаем id_common_sku из promo_n_plus_x_exception
    SELECT 
      pnpxe.*,
      sku.id_common_sku
    FROM public.promo_n_plus_x_exception pnpxe
    JOIN dwh.dim_sku sku ON pnpxe.id_sku = sku.id_sku
  ) pnpxe ON
    fss.id_client = pnpxe.id_client AND
    fss.tin_buyer = pnpxe.tin_buyer AND
    ( 
      fss.operation_date BETWEEN pnpxe.start_date AND pnpxe.end_date OR
      fss.operation_date BETWEEN pbi.start_date - (pbi.end_date - pbi.start_date) AND pbi.start_date-1
    ) AND
    sku.id_common_sku = pnpxe.id_common_sku
  WHERE 
    pnpxe.tin_buyer IS NULL AND
    fss.id_operation_type = 4 AND 
    fss.delete_date = '2000-01-01' AND
    fss.id_client IN (16, 28, 35, 36, 37, 418) AND
    (
      fss.operation_date BETWEEN pbi.start_date AND pbi.end_date OR
      fss.operation_date BETWEEN pbi.start_date - (pbi.end_date - pbi.start_date) AND pbi.start_date-1
    ) AND
    fss.id_operation_type = 4
),
-- Продажи без исключений (для total)
total_sales AS (
  SELECT 
    fss.*,
    sku.id_common_sku,
    pbi.id_promotion,
    pbi.id_promotion_type,
    pbi.start_date,
    pbi.end_date,
    CASE 
      WHEN fss.operation_date BETWEEN pbi.start_date AND pbi.end_date THEN 'total_promo'
      WHEN fss.operation_date BETWEEN pbi.start_date - (pbi.end_date - pbi.start_date) AND pbi.start_date-1 THEN 'total_control'
      ELSE NULL
    END AS sales_type
  FROM dwh.fct_sale_second fss
  JOIN dwh.dim_sku sku ON fss.id_sku = sku.id_sku
  JOIN promo_base_info pbi ON 
    sku.id_common_sku = pbi.id_common_sku AND
    fss.id_client = pbi.id_client
  WHERE 
    fss.delete_date = '2000-01-01' AND
    fss.id_client IN (16, 28, 35, 36, 37, 418) AND
    (
      fss.operation_date BETWEEN pbi.start_date AND pbi.end_date OR
      fss.operation_date BETWEEN pbi.start_date - (pbi.end_date - pbi.start_date) AND pbi.start_date-1
    )
),
-- Объединение данных
combined_sales AS (
  SELECT * FROM promo_condition_sales
  UNION ALL
  SELECT * FROM total_sales
),
-- Расчет количества и упаковок
sales_with_packs AS (
	SELECT 
	    cs.*,
	    calc.sales_quantity,
	    CASE 
	        WHEN cs.sales_type LIKE '%total%' THEN 
	            trunc(cs.quantity / (cs.id_promotion_type + 2))
	        ELSE 
	            trunc(calc.sales_quantity / (cs.id_promotion_type + 2))
	    END AS sales_pack
	FROM combined_sales cs,
	LATERAL (
	    SELECT 
	        CASE 
	            WHEN cs.sales_type LIKE '%total%' THEN cs.quantity
	            WHEN cs.id_client IN (36, 37) THEN
	                CASE 
	                    WHEN cs.quantity % (cs.id_promotion_type + 2) = 0 THEN cs.quantity 
	                    ELSE 0 
	                END
	            ELSE
	                CASE
	                    WHEN cs.quantity >= (cs.id_promotion_type + 2) THEN cs.quantity 
	                    ELSE 0 
	                END
	        END AS sales_quantity
	) calc
),
-- Агрегация
agg_table AS (
  SELECT 
    sales_type,
    id_promotion_type, 
    id_client, 
    start_date, 
    end_date, 
    id_common_sku, 
    id_promotion, 
    SUM(sales_quantity) AS sales_quantity, 
    SUM(sales_pack) AS sales_pack,
    COUNT(DISTINCT tin_buyer) AS acb
  FROM sales_with_packs
  WHERE sales_quantity != 0
  GROUP BY sales_type, id_promotion_type, id_client, start_date, end_date, id_common_sku, id_promotion
),
table_without_price AS (
-- Финальный результат
SELECT
  id_client, 
  start_date, 
  end_date, 
  id_common_sku, 
  id_promotion, 
  id_promotion_type,

  -- Промо и контроль с исключениями
  MAX(CASE WHEN sales_type = 'promo' THEN sales_quantity END) AS sales_quantity_promo,
  MAX(CASE WHEN sales_type = 'control' THEN sales_quantity END) AS sales_promo_control_period,
  
  -- Общие продажи (без исключений)
  MAX(CASE WHEN sales_type = 'total_promo' THEN sales_quantity END) AS total_sales,
  MAX(CASE WHEN sales_type = 'total_control' THEN sales_quantity END) AS total_sales_control_period,

  -- Упаковки (с исключениями)
  MAX(CASE WHEN sales_type = 'promo' THEN sales_pack END) AS sales_pack_promo,
  MAX(CASE WHEN sales_type = 'control' THEN sales_pack END) AS sales_pack_control,
  
  -- Упаковки (без исключений)
  MAX(CASE WHEN sales_type = 'total_promo' THEN sales_pack END) AS sales_pack_total_promo,
  MAX(CASE WHEN sales_type = 'total_control' THEN sales_pack END) AS sales_pack_total_control,

  -- ACB (с исключениями)
  MAX(CASE WHEN sales_type = 'promo' THEN acb END) AS acb_promo,
  MAX(CASE WHEN sales_type = 'control' THEN acb END) AS acb_control_period,
  
  -- ACB (без исключений)
  MAX(CASE WHEN sales_type = 'total_promo' THEN acb END) AS acb_total_promo,
  MAX(CASE WHEN sales_type = 'total_control' THEN acb END) AS acb_total_control
FROM agg_table
GROUP BY id_client, start_date, end_date, id_common_sku, id_promotion, id_promotion_type
)
select 
  twp.id_common_sku,
  common_sku.common_sku_name,
  twp.id_client,
  client.client_name,
  twp.id_promotion_type,
  promotion_type.promotion_type_name,
  twp.start_date,
  twp.end_date,
  twp.sales_quantity_promo,
  promo_price.bonus,
  sales_pack_promo,
  twp.sales_quantity_promo*promo_price.bonus as sales_amount_promo,
  sales_pack_promo*promo_price.bonus as sales_amount_pack_promo,
  twp.total_sales,
  twp.total_sales*promo_price.bonus as total_sales_amount,
  twp.total_sales_control_period,
  twp.total_sales_control_period*promo_price.bonus as total_sales_amount_control_period,
  twp.acb_promo,
  twp.acb_control_period,
  twp.sales_promo_control_period,
  twp.sales_promo_control_period*promo_price.bonus as sales_amount_promo_control_period
from table_without_price twp
left join dwh.dict_promotion_type promotion_type using(id_promotion_type)
left join (select distinct id_client, client_name from dwh.fct_client where delete_date is null ) client using(id_client)
left join dwh.dim_common_sku common_sku using(id_common_sku)
left join (select id_client, id_common_sku, sale_date, bonus from dwh.fct_promo_n_plus_x plus_x left join dwh.dim_sku using(id_sku) where plus_x.delete_date is null) promo_price 
on promo_price.id_client=twp.id_client and promo_price.id_common_sku=twp.id_common_sku and promo_price.sale_date = twp.start_date

