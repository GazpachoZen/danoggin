# Danoggin Engagement Metrics: Token Health vs Engagement Score

## Overview

The Danoggin analytics system tracks two key metrics for understanding notification delivery and user health: **Token Health** and **Engagement Score**. While related, they serve different purposes and provide complementary insights.

---

## Engagement Score (0-100)

### What It Measures
The engagement score is a calculated health assessment that represents how reliably we can deliver notifications to a user.

### How It's Calculated
The engagement score starts at **100 (perfect)** and gets reduced based on problems:

#### Score Reduction Factors:
1. **Token Failures** (up to -50 points):
   - Each failed notification attempt reduces the score by 10 points
   - Maximum reduction: 50 points (so 5+ failures = 50 point penalty)

2. **Time Since Last Success** (up to -30 points):
   - If it's been more than 7 days since a successful notification
   - Score decreases by 5 points per day beyond 7 days
   - Maximum reduction: 30 points

3. **Final score cannot go below 0**

### Score Interpretation:

#### **90-100: Healthy User** 🟢
- Notifications are delivering successfully
- No recent failures or minimal failures
- FCM tokens are working properly
- User is actively receiving notifications

#### **50-89: Declining User** 🟡  
- Some notification failures detected
- May indicate:
  - User uninstalled/reinstalled app (invalidating tokens)
  - Device issues or network problems
  - User disabled notifications
  - Token is getting stale

#### **0-49: Churned User** 🔴
- High number of notification failures
- Long time since successful notification (>7 days)
- Likely scenarios:
  - User uninstalled the app permanently
  - User switched devices without proper token refresh
  - User completely disabled notifications
  - Account is abandoned

#### **0 (No Data): New User** ⚪
- No notification attempts yet recorded
- User just signed up
- Normal for fresh accounts

### Real-World Examples:
- **Score 95:** User gets notifications successfully, maybe 1 recent failure
- **Score 75:** User had some token issues, maybe 2-3 failures in recent weeks  
- **Score 30:** User had many failures (5+) and hasn't received notifications in 10+ days
- **Score 0:** Either brand new user OR user with massive failure rate + very old failed attempts

---

## Token Health

### What It Measures
Raw notification delivery statistics showing the success rate of notification attempts.

### Format
- **Display:** "15/18 (83.3%)" 
- **Meaning:** 15 successful notifications out of 18 total attempts = 83.3% success rate

### Calculation
- **Simple math:** successful_notifications ÷ total_attempts × 100
- **All-time data:** Cumulative since analytics system started
- **Equal weighting:** All attempts weighted equally regardless of when they occurred

### Interpretation:
- **>90%:** Excellent token health, reliable delivery
- **70-90%:** Good health with some issues
- **50-70%:** Moderate health, investigate token problems
- **<50%:** Poor health, likely token issues or user churn
- **"No data":** No notification attempts recorded yet

---

## Engagement Score vs Token Health Comparison

| Aspect | Token Health | Engagement Score |
|--------|-------------|------------------|
| **Calculation** | Simple math: success/total | Complex: starts at 100, penalties applied |
| **Time Sensitivity** | All attempts weighted equally | Recent activity weighted more heavily |
| **Business Value** | Technical debugging | Strategic user management |
| **Action Trigger** | Low % = investigate token | Low score = consider user churned |
| **Data Scope** | All-time cumulative | Weighted with recency bias |
| **Format** | "X/Y (Z%)" | Single number 0-100 |

---

## How They Work Together

### **Example 1: Healthy User**
- **Token Health:** "50/52 (96.2%)" - Very high success rate
- **Engagement Score:** 95 - Excellent score because recent activity is good
- **Interpretation:** User is reliably receiving notifications

### **Example 2: Declining User** 
- **Token Health:** "8/15 (53.3%)" - Moderate success rate  
- **Engagement Score:** 65 - Declining because of recent failures
- **Interpretation:** User had early success but recent problems

### **Example 3: Churned User**
- **Token Health:** "12/25 (48.0%)" - Poor overall success rate
- **Engagement Score:** 25 - Very low because failures + no recent successes
- **Interpretation:** User likely abandoned, many failed attempts

### **Example 4: Recovering User**
- **Token Health:** "15/30 (50.0%)" - Poor overall rate due to early failures
- **Engagement Score:** 85 - High because recent notifications are succeeding  
- **Interpretation:** User had early token issues but is now healthy

---

## Why Both Metrics Matter

### **Token Health tells you:**
- "Is this user's FCM token working properly?"
- "What's their historical notification success rate?"
- "Do we have a technical delivery problem?"
- **Use for:** Technical debugging and infrastructure monitoring

### **Engagement Score tells you:**
- "Is this user still actively reachable?"
- "Should we worry about losing this user?"
- "Is this account worth keeping?"
- **Use for:** Business intelligence and user retention analysis

---

## Practical Applications in Danoggin

### **For Test Account Cleanup:**
- **Token Health:** Look for "0/0 (No data)" - never received notifications
- **Engagement Score:** 0 + name with numbers = likely test account

### **For User Retention:**
- **Token Health:** High percentage but recent failures = investigate token refresh
- **Engagement Score:** Declining trend = user may be at risk of churning

### **For System Health Monitoring:**
- **Token Health:** Overall success rates across all users (infrastructure health)
- **Engagement Score:** User distribution shows healthy vs churned population

### **For Support and Troubleshooting:**
- **Low Token Health + High Engagement Score:** Recent token issues, help user
- **High Token Health + Low Engagement Score:** Historical problems, investigate patterns
- **Both Low:** User likely churned, consider cleanup

---

## In the Enhanced ManageUsersTab

### **Visual Representation:**
- **Token Health Column:** Quick technical assessment for debugging
- **Engagement Score Column:** Business priority with color coding
  - 🟢 Green (>90): Healthy users
  - 🟡 Yellow (50-89): Declining users  
  - 🔴 Red (<50): Churned users
  - ⚪ Gray (0): No data/new users

### **Engagement Metrics Tab:**
- Detailed analysis combining both metrics
- Status assessment and recommendations
- Account analysis (test vs real user)

---

## Important Notes

### **For New Analytics System:**
- Current users will mostly show score 0 (no historical data yet)
- Scores become meaningful as Cloud Functions send notifications over time
- This is expected behavior for newly implemented analytics

### **Key Differences from User Engagement:**
- These metrics measure **notification delivery success**, not user engagement with app content
- A user could have high engagement score but never actually open the app
- Focus is on technical reachability, not behavioral engagement

### **Automatic Updates:**
- Both metrics are calculated and updated automatically by Cloud Functions
- No manual intervention required
- Data populates as notification sending occurs

---

## Conclusion

**Token Health** provides the raw technical data about notification delivery success rates, while **Engagement Score** provides a business-intelligence assessment of user reachability and account health. Together, they give you both the detailed technical picture and the strategic overview needed to maintain a healthy user base and reliable notification system.

The engagement score essentially answers: *"How confident are we that this user is still active and reachable?"* while token health answers: *"What percentage of our notification attempts to this user actually work?"*