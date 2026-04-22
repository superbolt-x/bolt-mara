{{ config (
    alias = target.database + '_blended_performance'
)}}

with
paid_data as
    (SELECT channel, campaign_id::varchar as campaign_id, campaign_name, adset_id::varchar as adset_id, adset_name, date::date, date_granularity, COALESCE(SUM(spend),0) as spend, COALESCE(SUM(clicks),0) as clicks, 
        COALESCE(SUM(impressions),0) as impressions, COALESCE(SUM(paid_purchases),0) as paid_purchases, COALESCE(SUM(paid_revenue),0) as paid_revenue, 
        0 as shopify_first_orders, 0 as shopify_orders, 0 as shopify_first_sales, 0 as shopify_sales, 0 as shopify_first_net_sales, 0 as shopify_net_sales
    FROM
        (SELECT 'Meta' as channel, campaign_id::varchar as campaign_id, campaign_name, adset_id::varchar as adset_id, adset_name, date, date_granularity, 
            spend, link_clicks as clicks, impressions, purchases as paid_purchases, revenue as paid_revenue
        FROM {{ source('reporting','facebook_ad_performance') }}
        UNION ALL
        SELECT 'Google Ads' as channel, campaign_id::varchar as campaign_id, campaign_name, '(not set)' as adset_id, '(not set)' as adset_name, date, date_granularity,
            spend, clicks, impressions, purchases as paid_purchases, revenue as paid_revenue
        FROM {{ source('reporting','googleads_campaign_performance') }}
        )
    GROUP BY channel, campaign_id, campaign_name, adset_id, adset_name, date, date_granularity),

sho_data as
    (SELECT
            'Shopify' as channel,
            '(not set)' as campaign_id,
            '(not set)' as campaign_name,
            '(not set)' as adset_id,
            '(not set)' as adset_name,
            date,
            date_granularity,
            0 as spend,
            0 as clicks,
            0 as impressions,
            0 as paid_purchases,
            0 as paid_revenue, 
            first_orders as shopify_first_orders, 
            orders as shopify_orders, 
            first_order_gross_sales as shopify_first_sales, 
            gross_sales as shopify_sales,
            first_order_net_sales as shopify_first_net_sales,
            net_sales as shopify_net_sales
        FROM {{ source('reporting','shopify_sales') }}
    )
    
SELECT 
    channel,
    campaign_id,
    campaign_name,
    adset_id,
    adset_name,
    date,
    date_granularity,
    sum(coalesce(spend,0)) AS spend,
    sum(coalesce(clicks,0)) AS clicks,
    sum(coalesce(impressions,0)) AS impressions,
    sum(coalesce(paid_purchases,0)) AS paid_purchases,
    sum(coalesce(paid_revenue,0)) AS paid_revenue,
    sum(coalesce(shopify_first_orders,0)) AS shopify_first_orders,
    sum(coalesce(shopify_orders,0)) AS shopify_orders,
    sum(coalesce(shopify_first_sales,0)) AS shopify_first_sales,
    sum(coalesce(shopify_sales,0)) AS shopify_sales,
    sum(coalesce(shopify_first_net_sales,0)) AS shopify_first_net_sales,
    sum(coalesce(shopify_net_sales,0)) AS shopify_net_sales
FROM (
    SELECT * FROM paid_data
    UNION ALL 
    SELECT * FROM sho_data
)
GROUP BY 1,2,3,4,5,6,7
