CREATE OR REPLACE VIEW public.promo_condition_sales_vw as(
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
      fss.operation_date BETWEEN pnpxe.start_date AND pnpxe.end_date
    ) AND
    sku.id_common_sku = pnpxe.id_common_sku
  WHERE 
    pnpxe.tin_buyer IS NULL AND
    fss.id_operation_type = 4 AND 
    fss.delete_date = '2000-01-01' AND
    fss.id_client IN (16, 35, 36, 37) AND
    (
      fss.operation_date BETWEEN pbi.start_date AND pbi.end_date
    ) AND
    fss.id_operation_type = 4
),
sales_with_packs AS (
	SELECT 
	    pcs.*,
	    calc.sales_quantity,
	    CASE 
	        WHEN pcs.sales_type LIKE '%total%' THEN 
	            trunc(pcs.quantity / (pcs.id_promotion_type + 2))
	        ELSE 
	            trunc(calc.sales_quantity / (pcs.id_promotion_type + 2))
	    END AS sales_pack
	FROM promo_condition_sales pcs,
	LATERAL (
	    SELECT 
	        CASE 
	            WHEN pcs.id_client IN (36, 37) THEN
	                CASE 
	                    WHEN pcs.quantity % (pcs.id_promotion_type + 2) = 0 THEN pcs.quantity 
	                    ELSE 0 
	                END
	            ELSE
	                CASE
	                    WHEN pcs.quantity >= (pcs.id_promotion_type + 2) THEN pcs.quantity 
	                    ELSE 0 
	                END
	        END AS sales_quantity
	) calc
)
SELECT id_client, id_sku, id_common_sku, operation_date, start_date, end_date, id_promotion_type+2 AS multiple, tin_buyer, sales_quantity
FROM sales_with_packs
WHERE sales_quantity > 0
)
