-- Новый вариант обновления N+X

--truncate table public.promotion_n_plus_x_report; -- очищаем таблицу


insert into public.promotion_n_plus_x_report -- загружаем новые данне
WITH second_sales_without_exceptions AS(
SELECT 
    fss.*,
    sku.id_common_sku
FROM dwh.fct_sale_second fss
LEFT JOIN public.promo_n_plus_x_exception pnpxe 
    ON fss.id_client = pnpxe.id_client
    AND fss.tin_buyer = pnpxe.tin_buyer
    AND fss.operation_date BETWEEN pnpxe.start_date AND pnpxe.end_date
    AND fss.id_sku = pnpxe.id_sku
    AND fss.id_operation_type = 4
LEFT JOIN dwh.dim_sku sku ON fss.id_sku = sku.id_sku
WHERE pnpxe.tin_buyer IS NULL
  AND fss.delete_date = '2000-01-01'
  AND fss.id_client IN (16, 28, 35, 36, 37, 418)
),
s AS (
  SELECT
    promotion.id_promotion_type, 
    promotion.id_client, 
    promotion.start_date, 
    promotion.end_date, 
    promo_sku.id_common_sku,
    --продано в акцию штук
    (
      select 
        sum(quantity) 
      from 
        second_sales_without_exceptions fss 
        left join dwh.dim_sku sku using(id_sku)
      where 
        fss.id_client = promotion.id_client 
        and fss.operation_date between promotion.start_date 
        and promotion.end_date 
        and fss.id_common_sku = promo_sku.id_common_sku 
        and --для протека и гк деление без остатка на кратность, для всех остальных > кратности
        (case 
	        when fss.id_client in (36,37) then case 
		        when promotion.id_promotion_type = 0 then fss.quantity % 2=0 
		        when promotion.id_promotion_type = 1 then fss.quantity % 3=0 
		        when promotion.id_promotion_type = 2 then fss.quantity %4=0
		        when promotion.id_promotion_type = 3 then fss.quantity %5=0
		    end
        else 
          case 
	          when promotion.id_promotion_type = 0 then fss.quantity >= 2 
	          when promotion.id_promotion_type = 1 then fss.quantity >= 3 
	          when promotion.id_promotion_type = 2 then fss.quantity >=4
	          when promotion.id_promotion_type = 3 then fss.quantity >=5 
	      end end 
        )
    ) as sales_quantity_promo,
--продано в акцию пакетов
       (
      select 
        sum(case 
	        when promotion.id_promotion_type = 0 then trunc(quantity / 2)
	        when promotion.id_promotion_type = 1 then trunc(quantity / 3)
	        when promotion.id_promotion_type = 2 then trunc(quantity / 4)
	        when promotion.id_promotion_type = 3 then trunc(quantity / 5)
	    end) 
      from 
        second_sales_without_exceptions fss 
        left join dwh.dim_sku sku using(id_sku) 
      where 
        fss.id_client = promotion.id_client 
        and fss.operation_date between promotion.start_date 
        and promotion.end_date 
        and fss.id_common_sku = promo_sku.id_common_sku 
        and --для протека и гк деление без остатка на кратность, для всех остальных > кратности
        (case 
	        when fss.id_client in (36,37) then case 
		        when promotion.id_promotion_type = 0 then fss.quantity % 2=0 
		        when promotion.id_promotion_type = 1 then fss.quantity % 3=0 
		        when promotion.id_promotion_type = 2 then fss.quantity %4=0 
		        when promotion.id_promotion_type = 3 then fss.quantity %5=0 
		    end
        else 
          case 
	          when promotion.id_promotion_type = 0 then fss.quantity >= 2
	          when promotion.id_promotion_type = 1 then fss.quantity >= 3
	          when promotion.id_promotion_type = 2 then fss.quantity >=4
	          when promotion.id_promotion_type = 3 then fss.quantity >=5
	      end end 
        )
    ) as sales_pack_promo,
    --акб в период акции
        (
      select 
        count(distinct tin_buyer) 
      from 
        second_sales_without_exceptions fss 
        left join dwh.dim_sku sku using(id_sku) 
      where 
        fss.id_client = promotion.id_client 
        and fss.operation_date between promotion.start_date 
        and promotion.end_date 
        and fss.id_common_sku = promo_sku.id_common_sku 
        and (
          case 
	          when fss.id_client in (36,37) then case 
		          when promotion.id_promotion_type = 0 then fss.quantity % 2=0 
		          when promotion.id_promotion_type = 1 then fss.quantity % 3=0 
		          when promotion.id_promotion_type = 2 then fss.quantity %4=0 
		          when promotion.id_promotion_type = 3 then fss.quantity %5=0 
		      end
        else 
          case 
	          when promotion.id_promotion_type = 0 then fss.quantity >= 2 
	          when promotion.id_promotion_type = 1 then fss.quantity >= 3 
	          when promotion.id_promotion_type = 2 then fss.quantity >=4 
	          when promotion.id_promotion_type = 3 then fss.quantity >=5 
	      end end
        )
    ) as acb_promo,
    --акб в контрольный период
    (select count(distinct tin_buyer)
    from second_sales_without_exceptions fss
    left join dwh.dim_sku sku using(id_sku)
    where 
      fss.id_client=promotion.id_client
      and promo_sku.id_common_sku=fss.id_common_sku
      and fss.operation_date between promotion.start_date -(
            promotion.end_date - promotion.start_date
          ) 
          and promotion.start_date - 1
          --выбираем только ИНН, которые участвовали в акции
    and fss.tin_buyer in (
        (
      select 
        distinct tin_buyer
      from 
        second_sales_without_exceptions fss 
        left join dwh.dim_sku sku using(id_sku) 
      where 
        fss.id_client = promotion.id_client 
        and fss.operation_date between promotion.start_date 
        and promotion.end_date 
        and fss.id_common_sku = promo_sku.id_common_sku 
        --вычитание списка исключений
        and (
          CASE
	          when fss.id_client in (36,37) then CASE 
		          when promotion.id_promotion_type = 0 then fss.quantity % 2=0 
		          when promotion.id_promotion_type = 1 then fss.quantity % 3=0 
		          when promotion.id_promotion_type = 2 then fss.quantity %4=0
		          when promotion.id_promotion_type = 3 then fss.quantity %5=0 
		      end
        else 
          CASE
	          when promotion.id_promotion_type = 0 then fss.quantity >= 2
	          when promotion.id_promotion_type = 1 then fss.quantity >= 3
	          when promotion.id_promotion_type = 2 then fss.quantity >=4 
	          when promotion.id_promotion_type = 3 then fss.quantity >=5 
	      end end
        )
    )
    )) as acb_control_period,
    --продажи в штуках в контрольный период сетям, которые участвовали в акции
    (select sum(quantity)
    from second_sales_without_exceptions fss
    left join dwh.dim_sku sku using(id_sku)
    where 
      fss.id_client=promotion.id_client
      and promo_sku.id_common_sku=fss.id_common_sku
      and fss.operation_date between promotion.start_date -(promotion.end_date - promotion.start_date)  and promotion.start_date - 1
        --выбираем только ИНН, которые участвовали в акции
    and fss.tin_buyer in (
        (
      select 
        distinct tin_buyer
      from 
        second_sales_without_exceptions fss 
        left join dwh.dim_sku sku using(id_sku) 
      where 
        fss.id_client = promotion.id_client 
        and fss.operation_date between promotion.start_date 
        and promotion.end_date 
        and fss.id_common_sku = promo_sku.id_common_sku 
        and (
          case 
	          when fss.id_client in (36,37) then case 
		          when promotion.id_promotion_type = 0 then fss.quantity % 2=0 
		          when promotion.id_promotion_type = 1 then fss.quantity % 3=0 
		          when promotion.id_promotion_type = 2 then fss.quantity %4=0
		          when promotion.id_promotion_type = 3 then fss.quantity %5=0 
		      end
        else 
          case 
	          when promotion.id_promotion_type = 0 then fss.quantity >= 2 
	          when promotion.id_promotion_type = 1 then fss.quantity >= 3 
	          when promotion.id_promotion_type = 2 then fss.quantity >=4
	          when promotion.id_promotion_type = 3 then fss.quantity >=5
	          end end
        )
    )
    )) as sales_promo_control_period,
    --всего продано всем в период акции
    (
      select 
        sum(quantity) 
      from 
        second_sales_without_exceptions fss 
        left join dwh.dim_sku sku using(id_sku) 
      where 
        fss.id_client = promotion.id_client 
        and fss.operation_date between promotion.start_date 
        and promotion.end_date 
        and sku.id_common_sku = promo_sku.id_common_sku
    ) as total_sales,
    --всего продано всем в контрольный период
    (
      select 
        sum(quantity) 
      from 
        second_sales_without_exceptions fss 
        left join dwh.dim_sku sku using(id_sku) 
      where 
        fss.id_client = promotion.id_client 
        and fss.operation_date between promotion.start_date -(
          promotion.end_date - promotion.start_date
        ) 
        and promotion.start_date - 1 
        and sku.id_common_sku = promo_sku.id_common_sku
    ) as total_sales_control_period 
  from 
    dwh.fct_promotion promotion 
    join dwh.lnk_promo_common_sku promo_sku on promotion.id_promotion = promo_sku.id_promotion 
    and promo_sku.delete_date is null 
  where 
    promotion.delete_date is null
    and promotion.start_date >= '2023-11-01'
)
select 
  s.id_common_sku,
  common_sku.common_sku_name,
  s.id_client,
  client.client_name,
  s.id_promotion_type,
  promotion_type.promotion_type_name,
  s.start_date,
  s.end_date,
  s.sales_quantity_promo,
  promo_price.bonus,
  sales_pack_promo,
  s.sales_quantity_promo*promo_price.bonus as sales_amount_promo,
  sales_pack_promo*promo_price.bonus as sales_amount_pack_promo,
  s.total_sales,
  s.total_sales*promo_price.bonus as total_sales_amount,
  s.total_sales_control_period,
  s.total_sales_control_period*promo_price.bonus as total_sales_amount_control_period,
  s.acb_promo,
  s.acb_control_period,
  s.sales_promo_control_period,
  s.sales_promo_control_period*promo_price.bonus as sales_amount_promo_control_period
from 
  s
left join dwh.dict_promotion_type promotion_type using(id_promotion_type)
left join (select distinct id_client, client_name from dwh.fct_client where delete_date is null ) client using(id_client)
left join dwh.dim_common_sku common_sku using(id_common_sku)
left join (select id_client, id_common_sku, sale_date, bonus from dwh.fct_promo_n_plus_x plus_x left join dwh.dim_sku using(id_sku) where plus_x.delete_date is null) promo_price 
on promo_price.id_client=s.id_client and promo_price.id_common_sku=s.id_common_sku and promo_price.sale_date = s.start_date --between s.start_date and s.end_date



SELECT *
FROM public.promotion_n_plus_x_report pnpxr 
