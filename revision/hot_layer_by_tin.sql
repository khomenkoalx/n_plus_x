SELECT 
    dcs.common_sku_name AS "Название товара", 
    vw.id_common_sku,
    fc.client_name AS "Клиент",
    COALESCE(dle.legal_entity_name, 'Одиночные аптеки') AS "Юридическое лицо покупателя",
    vw.tin_buyer AS "ИНН покупателя",
    vw.sales_multiple AS "Кратность по нашим данным",
    vw.promo_multiple AS "Кратность по данным итогов",
    vw.start_date AS "Дата начала", 
    vw.end_date AS "Дата окончания",
    COALESCE(vw.quantity_sales, 0) AS "Продано упаковок по нашим данным",
    COALESCE(vw.quantity_promo, 0) AS "Продано упаковок по данным итогов",
    COALESCE(vw.sales_bonus,0 ) AS "Бонус за пакет по нашим данным",
    COALESCE(vw.promo_bonus, 0) AS "Бонус за пакет по данным итогов",
    vw.promo_multiple - vw.sales_multiple AS "Разница кратности",
    COALESCE(vw.quantity_promo, 0) - COALESCE(vw.quantity_sales, 0) AS "Разница упаковок",
    COALESCE(vw.promo_bonus,0) - COALESCE(vw.sales_bonus,0) AS "Разница бонуса за упаковку",
    COALESCE(vw.sales_sum_bonus, 0) AS "Сумма бонуса по нашим данным",
    COALESCE(vw.promo_sum_bonus, 0) AS "Сумма бонуса по данным итогов",
    COALESCE(vw.promo_sum_bonus, 0) - COALESCE(vw.sales_sum_bonus, 0) AS "Разница суммы бонуса"
FROM public.promo_n_plus_x_revision_by_tin_vw vw
LEFT JOIN dwh.dim_common_sku dcs ON dcs.delete_date IS NULL AND dcs.id_common_sku = vw.id_common_sku
LEFT JOIN dwh.fct_client fc ON fc.delete_date IS NULL AND fc.id_client = vw.id_client 
    AND current_date BETWEEN fc.valid_from AND fc.valid_to 
LEFT JOIN dwh.dim_legal_entity dle ON dle.delete_date IS NULL 
    AND dle.id_legal_entity = vw.tin_buyer