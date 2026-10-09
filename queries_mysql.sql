-- ==========================================================
-- E-commerce Sales Analysis: MySQL queries (pure SQL)
-- Dataset: Olist Brazilian E-commerce (Kaggle)
-- Tables: customers, orders, order_items, products,
--         payments, category_translation
-- Requires MySQL 8.0+ (uses CTEs and window functions)
-- Run one query at a time: select it, then press Ctrl + Enter
-- ==========================================================

USE olist;

-- ----------------------------------------------------------
-- 1. Order status breakdown
-- ----------------------------------------------------------
SELECT order_status, COUNT(*) AS total_orders
FROM orders
GROUP BY order_status
ORDER BY total_orders DESC;

-- ----------------------------------------------------------
-- 2. KPIs: total revenue, total orders, average order value
-- ----------------------------------------------------------
SELECT ROUND(SUM(oi.price), 2) AS total_revenue,
       COUNT(DISTINCT o.order_id) AS total_orders,
       ROUND(SUM(oi.price) / COUNT(DISTINCT o.order_id), 2) AS avg_order_value
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered';

-- ----------------------------------------------------------
-- 3. Monthly revenue (full months only: Jan 2017 - Aug 2018)
-- ----------------------------------------------------------
SELECT DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS month,
       ROUND(SUM(oi.price), 2) AS revenue,
       COUNT(DISTINCT o.order_id) AS orders
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp >= '2017-01-01'
  AND o.order_purchase_timestamp <  '2018-09-01'
GROUP BY month
ORDER BY month;

-- ----------------------------------------------------------
-- 4. Month-over-month revenue growth (CTE + window function)
-- ----------------------------------------------------------
WITH monthly AS (
    SELECT DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS month,
           SUM(oi.price) AS revenue
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp <  '2018-09-01'
    GROUP BY month
)
SELECT month,
       ROUND(revenue, 2) AS revenue,
       ROUND((revenue - LAG(revenue) OVER (ORDER BY month)) * 100
             / LAG(revenue) OVER (ORDER BY month), 1) AS growth_pct
FROM monthly
ORDER BY month;

-- ----------------------------------------------------------
-- 5. Best month (highest revenue)
-- ----------------------------------------------------------
SELECT DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS month,
       ROUND(SUM(oi.price), 2) AS revenue
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp >= '2017-01-01'
  AND o.order_purchase_timestamp <  '2018-09-01'
GROUP BY month
ORDER BY revenue DESC
LIMIT 1;

-- ----------------------------------------------------------
-- 6. Top 10 categories by revenue, with % of total revenue
-- ----------------------------------------------------------
SELECT COALESCE(t.product_category_name_english, 'unknown') AS category,
       ROUND(SUM(oi.price), 2) AS revenue,
       COUNT(DISTINCT oi.order_id) AS orders,
       ROUND(SUM(oi.price) * 100 / (
             SELECT SUM(oi2.price)
             FROM order_items oi2
             JOIN orders o2 ON oi2.order_id = o2.order_id
             WHERE o2.order_status = 'delivered'), 1) AS revenue_share_pct
FROM order_items oi
JOIN orders o   ON oi.order_id = o.order_id
JOIN products p ON oi.product_id = p.product_id
LEFT JOIN category_translation t ON p.product_category_name = t.product_category_name
WHERE o.order_status = 'delivered'
GROUP BY category
ORDER BY revenue DESC
LIMIT 10;

-- ----------------------------------------------------------
-- 7. Top 10 customer states by revenue, with % of total
-- ----------------------------------------------------------
SELECT c.customer_state AS state,
       ROUND(SUM(oi.price), 2) AS revenue,
       COUNT(DISTINCT o.order_id) AS orders,
       ROUND(SUM(oi.price) * 100 / (
             SELECT SUM(oi2.price)
             FROM order_items oi2
             JOIN orders o2 ON oi2.order_id = o2.order_id
             WHERE o2.order_status = 'delivered'), 1) AS revenue_share_pct
FROM orders o
JOIN customers c    ON o.customer_id = c.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY state
ORDER BY revenue DESC
LIMIT 10;

-- ----------------------------------------------------------
-- 8. Delivery performance: average days and % delivered late
-- ----------------------------------------------------------
SELECT ROUND(AVG(TIMESTAMPDIFF(SECOND, order_purchase_timestamp,
                               order_delivered_customer_date) / 86400), 1) AS avg_delivery_days,
       ROUND(SUM(order_delivered_customer_date > order_estimated_delivery_date)
             * 100 / COUNT(*), 1) AS late_delivery_pct
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL;

-- ----------------------------------------------------------
-- 9. Payment methods, with % share of payment value
-- ----------------------------------------------------------
SELECT payment_type,
       COUNT(*) AS payments,
       ROUND(SUM(payment_value), 2) AS total_value,
       ROUND(SUM(payment_value) * 100 / SUM(SUM(payment_value)) OVER (), 1) AS share_pct
FROM payments
GROUP BY payment_type
ORDER BY total_value DESC;

-- ----------------------------------------------------------
-- 10. Repeat customers: how many customers ordered 2+ times
--     (customer_unique_id = the real customer)
-- ----------------------------------------------------------
SELECT COUNT(*) AS total_customers,
       SUM(order_count > 1) AS repeat_customers,
       ROUND(SUM(order_count > 1) * 100 / COUNT(*), 1) AS repeat_rate_pct
FROM (
    SELECT c.customer_unique_id, COUNT(DISTINCT o.order_id) AS order_count
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
) AS customer_orders;

-- ----------------------------------------------------------
-- 11. BONUS: Top 10 customers by total spend (RANK window function)
-- ----------------------------------------------------------
SELECT customer_unique_id, total_spent, spend_rank
FROM (
    SELECT c.customer_unique_id,
           ROUND(SUM(oi.price), 2) AS total_spent,
           RANK() OVER (ORDER BY SUM(oi.price) DESC) AS spend_rank
    FROM orders o
    JOIN customers c    ON o.customer_id = c.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
) AS ranked
WHERE spend_rank <= 10
ORDER BY spend_rank;
