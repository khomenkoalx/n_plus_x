
SELECT 
    dcs.common_sku_name AS "Название товара", 
    vw.id_common_sku,
    fc.client_name AS "Клиент",
    COALESCE(dle.legal_entity_name, 'Одиночные аптеки') AS "Юридическое лицо покупателя",
    vw.tin_buyer AS "ИНН покупателя",
    (vw.sales_multiple - 1) || '+1' AS "Кратность по нашим данным",
    (vw.promo_multiple - 1) || '+1' AS "Кратность по данным итогов",
    vw.start_date AS "Дата начала", 
    vw.end_date AS "Дата окончания",
    vw.quantity_sales AS "Продано упаковок по нашим данным",
    vw.quantity_promo AS "Продано упаковок по данным итогов",
    vw.sales_bonus AS "Бонус за пакет по нашим данным",
    vw.promo_bonus AS "Бонус за пакет по данным итогов",
    vw.promo_multiple - vw.sales_multiple AS "Разница кратности",
    COALESCE(vw.quantity_promo, 0) - vw.quantity_sales AS "Разница упаковок",
    vw.promo_bonus - vw.sales_bonus AS "Разница бонуса за упаковку",
    vw.sales_sum_bonus AS "Сумма бонуса по нашим данным",
    vw.promo_sum_bonus AS "Сумма бонуса по данным итогов",
    COALESCE(vw.promo_sum_bonus, 0) - vw.sales_sum_bonus AS "Разница суммы бонуса"
FROM public.promo_n_plus_x_revision_by_tin_vw vw
LEFT JOIN dwh.dim_common_sku dcs ON dcs.delete_date IS NULL AND dcs.id_common_sku = vw.id_common_sku
LEFT JOIN dwh.fct_client fc ON fc.delete_date IS NULL AND fc.id_client = vw.id_client 
    AND current_date BETWEEN fc.valid_from AND fc.valid_to 
LEFT JOIN dwh.dim_legal_entity dle ON dle.delete_date IS NULL 
    AND dle.id_legal_entity = vw.tin_buyer