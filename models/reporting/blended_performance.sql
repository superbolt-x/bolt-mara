{{ config (
    alias = target.database + '_blended_performance'
)}}

{%- set date_granularity_list = ['day','week','month','quarter','year'] -%}


WITH orders AS (
  SELECT order_id FROM {{ source('reporting','shopify_daily_sales_by_order') }}
  WHERE order_tags !~* 'GIFTING'
  AND order_tags !~* 'TEST'
  AND order_tags !~* 'ShopMy Gifting'
  AND order_tags !~* 'SEND OUT'
)
  
  refund_order_data AS
    (SELECT date, day, week, month, quarter, year, 
        order_id, customer_order_index, gross_revenue, total_revenue, subtotal_discount, shipping_price, total_tax, shipping_discount, 0 as subtotal_refund, 0 as shipping_refund, 0 as tax_refund
    FROM {{ source('reporting','shopify_daily_sales_by_order') }}
    WHERE order_id IN (SELECT * FROM orders)
    UNION ALL
    SELECT date, day, week, month, quarter, year, 
        null as order_id, customer_order_index, 0 as gross_revenue, 0 as total_revenue, 0 as subtotal_discount, 0 as shipping_price, 0 as total_tax, 0 as shipping_discount, subtotal_refund, shipping_refund, tax_refund 
    FROM {{ source('reporting','shopify_daily_refunds') }}
    WHERE order_id IN (SELECT * FROM orders)),
    
    initial_sho_data AS (
        {% for granularity in date_granularity_list %}
        SELECT 
            '{{granularity}}' as date_granularity,
            {{granularity}} as date,
            COUNT(DISTINCT order_id) as shopify_orders, 
            COUNT(DISTINCT CASE WHEN customer_order_index = 1 THEN order_id END) as shopify_first_orders,
            SUM(COALESCE(gross_revenue,0)-COALESCE(subtotal_discount,0)+COALESCE(total_tax,0)+COALESCE(shipping_price,0)-COALESCE(shipping_discount,0)) as shopify_sales,
            SUM(CASE WHEN customer_order_index = 1 THEN COALESCE(gross_revenue,0)-COALESCE(subtotal_discount,0)+COALESCE(total_tax,0)+COALESCE(shipping_price,0)-COALESCE(shipping_discount,0) END) as shopify_first_sales,
            SUM(COALESCE(subtotal_refund,0)-COALESCE(shipping_refund,0)+COALESCE(tax_refund,0)) as shopify_refund,
            SUM(CASE WHEN customer_order_index = 1 THEN COALESCE(subtotal_refund,0)-COALESCE(shipping_refund,0)+COALESCE(tax_refund,0) END) as shopify_first_refund
        FROM refund_order_data
        GROUP BY date_granularity, {{granularity}}
        {% if not loop.last %}UNION ALL{% endif %}
        {% endfor %}
    ),
    
paid_data as
    (SELECT channel, campaign_id::varchar as campaign_id, campaign_name, date::date, date_granularity, COALESCE(SUM(spend),0) as spend, COALESCE(SUM(clicks),0) as clicks, 
        COALESCE(SUM(impressions),0) as impressions, COALESCE(SUM(paid_purchases),0) as paid_purchases, COALESCE(SUM(paid_revenue),0) as paid_revenue, 
        0 as shopify_first_orders, 0 as shopify_orders, 0 as shopify_first_sales, 0 as shopify_sales, 0 as shopify_first_net_sales, 0 as shopify_net_sales
    FROM
        (SELECT 'Meta' as channel, campaign_id::varchar as campaign_id, campaign_name, date, date_granularity, 
            spend, link_clicks as clicks, impressions, purchases as paid_purchases, revenue as paid_revenue
        FROM {{ source('reporting','facebook_campaign_performance') }}
        UNION ALL
        SELECT 'Google Ads' as channel, campaign_id::varchar as campaign_id, campaign_name, date, date_granularity,
            spend, clicks, impressions, purchases as paid_purchases, revenue as paid_revenue
        FROM {{ source('reporting','googleads_campaign_performance') }}
        )
    GROUP BY channel, campaign_id, campaign_name, date, date_granularity),

sho_data as
    (SELECT
            'Shopify' as channel,
            '(not set)' as campaign_name,
            date,
            date_granularity,
            0 as spend,
            0 as clicks,
            0 as impressions,
            0 as paid_purchases,
            0 as paid_revenue, 
            COALESCE(shopify_first_orders,0) as shopify_first_orders, 
            COALESCE(shopify_orders,0) as shopify_orders, 
            COALESCE(shopify_first_sales,0) as shopify_first_sales, 
            COALESCE(shopify_sales,0) as shopify_sales,
            COALESCE(shopify_first_sales,0)-COALESCE(shopify_first_refund,0) as shopify_first_net_sales,
            COALESCE(shopify_sales,0)-COALESCE(shopify_refund,0) as shopify_net_sales
        FROM initial_sho_data 
    )
    
SELECT 
    channel,
    campaign_name,
    date,
    date_granularity,
    spend,
    clicks,
    impressions,
    paid_purchases,
    paid_revenue,
    shopify_first_orders,
    shopify_orders,
    shopify_first_sales,
    shopify_sales,
    shopify_first_net_sales,
    shopify_net_sales
FROM (
    SELECT * FROM paid_data
    UNION ALL 
    SELECT * FROM sho_data
)
