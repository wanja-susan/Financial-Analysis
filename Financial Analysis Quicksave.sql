# 1. Overall Financial Performance
-- Q1. What was the total revenue from transaction fees and subscriptions?
with total_revenue as
	(SELECT
		(SELECT sum(fee_amount) FROM  transactions) AS transaction_revenue,
		(SELECT SUM(fee_amount) FROM subscriptions) AS subscription_revenue)
SELECT
  transaction_revenue,
  subscription_revenue,
  transaction_revenue + subscription_revenue AS total_revenue
FROM total_revenue;

-- Q2: What was the monthly revenue trend — were there spikes or drops?
WITH transaction_cte AS (
  SELECT
    MONTH(date) AS month_num,
    MONTHNAME(date) AS month_name,
    SUM(fee_amount) AS transaction_revenue
  FROM transactions
  WHERE YEAR(date) = 2024
  GROUP BY MONTH(date), MONTHNAME(date)
),
subscription_cte AS (
  SELECT
    MONTH(start_date) AS month_num,
    MONTHNAME(start_date) AS month_name,
    SUM(fee_amount) AS subscription_revenue
  FROM subscriptions
  WHERE YEAR(start_date) = 2024
  GROUP BY MONTH(start_date), MONTHNAME(start_date)
),
combined_cte AS (
  SELECT 
    t.month_num,
    t.month_name,
    t.transaction_revenue,
    s.subscription_revenue
  FROM transaction_cte t
  LEFT JOIN subscription_cte s ON t.month_num = s.month_num

  UNION

  SELECT 
    s.month_num,
    s.month_name,
    t.transaction_revenue,
    s.subscription_revenue
  FROM subscription_cte s
  LEFT JOIN transaction_cte t ON s.month_num = t.month_num
)
SELECT 
  month_num,
  month_name,
  COALESCE(transaction_revenue, 0) AS transaction_revenue,
  COALESCE(subscription_revenue, 0) AS subscription_revenue,
  COALESCE(transaction_revenue, 0) + COALESCE(subscription_revenue, 0) AS total_revenue
FROM combined_cte
ORDER BY month_num;

-- Q3: What is the average revenue per user (ARPU), and how does it vary by user type?
SELECT
  u.plan_name,
  ROUND(SUM(t.fee_amount) + COALESCE(SUM(s.fee_amount), 0), 2) / COUNT(DISTINCT u.user_id) AS arpu
FROM quicksave_users u
LEFT JOIN transactions t ON u.user_id = t.user_id
LEFT JOIN subscriptions s ON u.user_id = s.user_id
GROUP BY u.plan_name;

--  2. User Segmentation & Profitability

-- Q4: Which user types (e.g., Students, Gig Workers, Business Owners) are the most profitable?
SELECT
  u.user_type,
  SUM(t.fee_amount) AS transaction_revenue,
  SUM(s.fee_amount) AS subscription_revenue
FROM quicksave_users u
LEFT JOIN transactions t ON u.user_id = t.user_id
LEFT JOIN subscriptions s ON u.user_id = s.user_id
GROUP BY u.user_type;


-- Q5: What’s the revenue breakdown by plan name (Free vs Premium)?
WITH txn_rev AS (
  SELECT user_id, SUM(fee_amount) AS txn_revenue
  FROM transactions
  GROUP BY user_id
),
sub_rev AS (
  SELECT user_id, SUM(fee_amount) AS sub_revenue
  FROM subscriptions
  GROUP BY user_id
)
SELECT 
  u.plan_name,
  ROUND(SUM(COALESCE(t.txn_revenue, 0) + COALESCE(s.sub_revenue, 0)), 2) AS total_revenue
FROM quicksave_users u
LEFT JOIN txn_rev t ON u.user_id = t.user_id
LEFT JOIN sub_rev s ON u.user_id = s.user_id
GROUP BY u.plan_name;


-- Q6: Classify users into profit tiers (Profitable, Marginal, Loss).
WITH user_revenue AS (
  SELECT
    u.user_id,
  ROUND(SUM(t.fee_amount) + COALESCE(SUM(s.fee_amount), 0), 2) AS total_revenue
  FROM quicksave_users u
  LEFT JOIN transactions t ON u.user_id = t.user_id
  LEFT JOIN subscriptions s ON u.user_id = s.user_id
  GROUP BY u.user_id
)
SELECT *,
  CASE
    WHEN total_revenue >= 10 THEN 'Profitable'
    WHEN total_revenue BETWEEN 5 AND 9.99 THEN 'Marginal'
    ELSE 'Loss'
  END AS profitability_tier
FROM user_revenue;

-- 3. Goal-Based Behavior

-- Q7: What are the top goal categories by transaction volume and fee revenue?
SELECT
  g.goal_name,
  COUNT(t.transaction_id) AS transaction_count,
  SUM(t.fee_amount) AS fee_revenue
FROM transactions t
JOIN goals g ON t.goal_id = g.goal_id
GROUP BY g.goal_name
ORDER BY fee_revenue DESC
LIMIT 5;

-- Q8: Are users pursuing high-target goals more engaged or profitable?
SELECT
  g.goal_name,
  AVG(g.target_amount) AS avg_target,
  COUNT(t.transaction_id) AS txn_count, -- txn(transaction)
  SUM(t.fee_amount) AS fee_revenue
FROM goals g
JOIN transactions t ON g.goal_id = t.goal_id
GROUP BY g.goal_name
HAVING avg_target >= 1000
ORDER BY fee_revenue DESC;
-- users pursuing high-target goals like Home Renovation and Retirement appear to be more engaged (txn_count) and more profitable (fee_revenue).

-- 4. Engagement & Usage Trends
-- Q9: What is the monthly active user (MAU) trend in 2024?
SELECT
  MONTHNAME(date) AS month,
  COUNT(DISTINCT user_id) AS active_users
FROM transactions
GROUP BY MONTHNAME(date)
ORDER BY active_users DESC;

-- Q10: How many users made repeat transactions, and how frequently?
SELECT
  user_id,
  COUNT(transaction_id) AS txn_count
FROM transactions
GROUP BY user_id
HAVING txn_count > 1
ORDER BY txn_count DESC;

-- 5. ROI and Strategic Value

-- Q11: What is the estimated cost per user vs revenue per user (ROI estimate)?
WITH revenue AS (
  SELECT
    u.user_id,
      ROUND(SUM(t.fee_amount) + COALESCE(SUM(s.fee_amount), 0), 2) AS total_revenue
  FROM quicksave_users u
  LEFT JOIN transactions t ON u.user_id = t.user_id
  LEFT JOIN subscriptions s ON u.user_id = s.user_id
  GROUP BY u.user_id
)
SELECT
  user_id,
  total_revenue,
  5 AS est_cost_per_user,
  total_revenue - 5 AS estimated_roi
FROM revenue;

-- Q12: What percentage of users are break-even or better?
WITH revenue AS (
  SELECT
    u.user_id,
	ROUND(SUM(t.fee_amount) + COALESCE(SUM(s.fee_amount), 0), 2) AS total_revenue
  FROM quicksave_users u
  LEFT JOIN transactions t ON u.user_id = t.user_id
  LEFT JOIN subscriptions s ON u.user_id = s.user_id
  GROUP BY u.user_id
)
SELECT
  COUNT(*) AS total_users,
  SUM(CASE WHEN total_revenue >= 5 THEN 1 ELSE 0 END) AS breakeven_or_better,
  ROUND(100.0 * SUM(CASE WHEN total_revenue >= 5 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_breakeven
FROM revenue;

-- Q13: Are we retaining and monetizing Premium users effectively?
SELECT
  u.plan_name,
  COUNT(DISTINCT u.user_id) AS users,
	ROUND(SUM(t.fee_amount) + COALESCE(SUM(s.fee_amount), 0), 2) AS total_revenue
FROM quicksave_users u
LEFT JOIN transactions t ON u.user_id = t.user_id
LEFT JOIN subscriptions s ON u.user_id = s.user_id
WHERE u.plan_name = 'Premium'
GROUP BY u.plan_name;
