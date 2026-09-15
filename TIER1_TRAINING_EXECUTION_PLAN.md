# Tier 1 Training 実施計画
## Sep 16-22, 2026 | Platform Basics Training

**作成日**: Sep 15, 2026  
**対象**: 42 FTE全員  
**目標**: 95%以上完了、80%以上合格  
**Hard Deadline**: Sep 22, 2026 17:00 JST

---

## 📋 概要

Safy Production Sprint開始に向けて、全42名メンバーを対象にTier 1 Training（基礎研修）を実施。Platform技術、Operations、Content、Marketing各分野の必須知識を習得し、Production readinessを達成する。

---

## 🎯 Learning Objectives

### Platform技術 (Session A)
```
✓ Firebase ecosystem understanding
✓ Cloud Functions deployment & monitoring
✓ Firestore architecture & security
✓ Production deployment procedures
✓ Performance optimization basics
```

### Operations (Session B)
```
✓ Monitoring & alerting setup
✓ Incident response procedures
✓ Performance baseline metrics
✓ Error handling & debugging
✓ 24/7 support structure
```

### Content Production (Session C)
```
✓ Course creation workflow
✓ Quality assurance process
✓ Localization procedures
✓ Content calendar management
✓ Production acceleration tactics
```

### GTM Strategy (Session D)
```
✓ Market positioning
✓ Influencer partnerships
✓ Paid acquisition strategy
✓ Launch timeline (Nov 1, Dec 1)
✓ Success metrics & KPIs
```

---

## 📅 Training Schedule

### Sep 16 (Monday)

#### 08:00-12:00 JST: Session A - Platform技術概要

**Instructor**: Backend Lead + Frontend Lead  
**Venue**: Engineering meeting room (or Zoom)  
**Attendees**: Group A (15 FTE)
- Backend engineers (8)
- Frontend engineers (5)
- DevOps/Infra (2)

**Agenda** (4時間):
```
08:00-08:15  Welcome & agenda (15 min)
08:15-09:00  Firebase ecosystem overview (45 min)
  - Core services: Auth, Firestore, Functions, Storage
  - Regional setup: asia-northeast1
  - Pricing model & quotas
  - Security model overview

09:00-09:45  Cloud Functions deployment (45 min)
  - Node.js 20.x runtime
  - TypeScript setup & build
  - Secrets management
  - Production deployment checklist

09:45-10:00  Break (15 min)

10:00-10:45  Firestore architecture (45 min)
  - Collections & documents
  - Security rules deep dive
  - Indexing strategy
  - Query performance

10:45-11:15  Production readiness (30 min)
  - Performance baselines
  - Monitoring setup
  - Alerting configuration
  - Incident response

11:15-11:45  Live demo: Deploy a function (30 min)
  - Create → Test → Deploy → Monitor
  - Real-time log viewing
  - Error handling walkthrough

11:45-12:00  Q&A + Assessment intro (15 min)
```

**Materials**:
- Slides: `docs/firebase-technical-overview.pdf`
- Code samples: `functions/src/examples/`
- Runbook: `docs/production-deployment-runbook.md`

**Assessment**:
- Quiz (20 min after Session A ends)
- Topics: Firebase architecture, deployment, security
- Pass threshold: 80%

---

#### 13:00-17:00 JST: Session B - Operations・監視体制

**Instructor**: Infrastructure Lead + QA Lead  
**Venue**: Operations meeting room (or Zoom)  
**Attendees**: Group B (14 FTE)
- QA engineers (6)
- Support team (4)
- Operations (3)
- Developers rotation (1)

**Agenda** (4時間):
```
13:00-13:15  Welcome & Session B overview (15 min)

13:15-14:00  Monitoring & alerting setup (45 min)
  - Google Cloud Console
  - Metrics: Latency, Error rate, CPU, Memory
  - Alert rules configuration
  - Slack integration

14:00-14:45  Performance optimization (45 min)
  - Performance baseline metrics
  - Identifying bottlenecks
  - Optimization techniques
  - Load testing basics

14:45-15:00  Break (15 min)

15:00-15:45  Error handling & debugging (45 min)
  - Cloud Functions logs
  - Error tracking
  - Debugging techniques
  - Common issues & solutions

15:45-16:30  Support procedures (45 min)
  - Incident severity classification
  - Escalation procedures
  - Customer communication
  - Postmortem process

16:30-16:45  Live demo: Monitor & debug (15 min)
  - View live logs
  - Identify anomalies
  - Trigger alert

16:45-17:00  Q&A + Assessment intro (15 min)
```

**Materials**:
- Slides: `docs/operations-monitoring-guide.pdf`
- Runbook: `docs/incident-response-runbook.md`
- Monitoring dashboard: [link to GCP Console]

**Assessment**:
- Quiz (20 min after Session B ends)
- Topics: Monitoring, performance, debugging, support
- Pass threshold: 80%

---

### Sep 17 (Tuesday)

#### 08:00-12:00 JST: Session C - Content Production Flow

**Instructor**: Content Lead  
**Venue**: Content team room (or Zoom)  
**Attendees**: Group C (13 FTE)
- Content creators (5)
- QA testers (4)
- Product/Design (3)
- Rotating others (1)

**Agenda** (4時間):
```
08:00-08:15  Welcome & overview (15 min)

08:15-09:00  Course creation workflow (45 min)
  - Course structure & modules
  - Lesson design best practices
  - Quiz question creation
  - Content calendar

09:00-09:45  Quality assurance process (45 min)
  - QA checklist
  - Review process
  - Feedback incorporation
  - Sign-off procedures

09:45-10:00  Break (15 min)

10:00-10:45  Localization procedures (45 min)
  - 8 language support strategy
  - Translation workflow
  - Cultural adaptation
  - Testing in different languages

10:45-11:15  Content calendar & production (30 min)
  - Nov-Dec schedule
  - Production targets
  - Team coordination
  - Resource planning

11:15-11:45  Live demo: Create a course (30 min)
  - Outline → Lesson → Quiz
  - Firestore submission
  - QA workflow walkthrough

11:45-12:00  Q&A + Assessment intro (15 min)
```

**Materials**:
- Slides: `docs/content-production-guide.pdf`
- Templates: `templates/lesson-template.md`
- Runbook: `docs/content-qc-runbook.md`

**Assessment**:
- Quiz (20 min after Session C ends)
- Topics: Course structure, QA, localization
- Pass threshold: 80%

---

#### 13:00-17:00 JST: Session D - GTM Strategy

**Instructor**: Marketing Lead  
**Venue**: Marketing meeting room (or Zoom)  
**Attendees**: Group D (各チーム数名)
- Marketing team (8)
- Product managers (2)
- Business development (2)
- Rotating engineers (2)

**Agenda** (4時間):
```
13:00-13:15  Welcome & GTM overview (15 min)

13:15-14:00  Market positioning (45 min)
  - Target market: 企業研修向けSaaS
  - Competitive landscape
  - Unique value proposition
  - Pricing strategy

14:00-14:45  Influencer partnerships (45 min)
  - Influencer list (50+ creators)
  - Partnership tiers & terms
  - Contract negotiation
  - Campaign calendar

14:45-15:00  Break (15 min)

15:00-15:45  Paid acquisition strategy (45 min)
  - Ad platform setup (Google Ads, Facebook)
  - Budget allocation ($50K)
  - Campaign structure
  - Performance metrics

15:45-16:30  Launch timeline (45 min)
  - Nov 1: Soft launch (5M users target)
  - Dec 1: Full launch (5M+ users target)
  - Press campaign
  - Social media strategy

16:30-16:45  Success metrics & KPIs (15 min)
  - DAU/MAU targets
  - Retention metrics
  - Revenue targets
  - Marketing ROI

16:45-17:00  Q&A + Assessment intro (15 min)
```

**Materials**:
- Slides: `docs/gtm-strategy-overview.pdf`
- Influencer list: `data/influencers-2026.csv`
- Budget tracker: [link to spreadsheet]

**Assessment**:
- Quiz (20 min after Session D ends)
- Topics: Market positioning, GTM, partnerships
- Pass threshold: 80%

---

### Sep 18-19 (Wed-Thu): Individual Support & Catch-up

**Objective**: Absences対応 + Low performers向けサポート

#### 18:00-19:00 JST (Evening sessions, 各日)
- 1-on-1 tutor sessions
- Quiz retake opportunity
- Materials復習
- Q&A

**Instructors**: Training Lead + Session instructors

**Participants**: TBD (absences, low performers)

---

### Sep 21 (Friday): Tier 1 Completion Verification

#### 14:00-15:30 JST: Results Review Meeting

**Participants**: Training Lead, Instructors, Managers

**Agenda**:
```
14:00-14:15  Assessment results summary (15 min)
  - Pass/fail breakdown
  - Average score
  - Distribution analysis

14:15-14:45  Individual review (30 min)
  - High performers: Recognized
  - Low performers: Support offered
  - Attendance: Flagged if <95%

14:45-15:15  Feedback analysis (30 min)
  - Training feedback survey results
  - Improvement areas
  - Session ratings

15:15-15:30  GATE 3 preparation (15 min)
  - Sep 23 GATE 3 agenda
  - Engineering status: 75%+ APIs?
  - Production Sprint readiness check
```

**Output**:
- [ ] Completion certificate: Issued to all
- [ ] Support plan: For low performers
- [ ] Training feedback: Documented
- [ ] GATE 3 agenda: Finalized

---

### Sep 22 (Saturday): Week 2 Retrospective & GATE 3 Final Prep

#### 10:00-11:30 JST: Team Retrospective

**Participants**: All trainers, managers, executive leads

**Agenda**:
```
10:00-10:20  Training effectiveness (20 min)
  - Completion rate: 95%+ verified
  - Learning outcomes: Assessed
  - Feedback incorporation

10:20-10:50  Tier 2 curriculum finalization (30 min)
  - Role-specific training modules
  - Sep 23-Oct 31 schedule
  - Instructor assignments

10:50-11:20  Production Sprint alignment (30 min)
  - GATE 3 verification: Sep 23
  - Engineering 75%+ APIs readiness
  - Team readiness: Confirmed
  - Production launch timeline locked

11:20-11:30  Next week preview (10 min)
  - Sep 23: Production Sprint Launch
  - Daily standups: Begin
  - GATE 3 verification: Execute
```

**Output**:
- [ ] Tier 1 training: 95%+ completion confirmed
- [ ] GATE 3 agenda: Final confirmed
- [ ] Sep 23 kickoff: Team briefed

---

## ✅ Assessment & Success Criteria

### Quiz Format

**Type**: Multiple choice (20 questions)  
**Duration**: 20 minutes  
**Time**: After each session (same day)  
**Pass threshold**: 80% (16/20 correct)

### Assessment Topics by Session

**Session A (Platform)**:
- Firebase services (5 Q)
- Cloud Functions (5 Q)
- Firestore (5 Q)
- Security model (5 Q)

**Session B (Operations)**:
- Monitoring (5 Q)
- Performance (5 Q)
- Debugging (5 Q)
- Support (5 Q)

**Session C (Content)**:
- Course structure (5 Q)
- QA process (5 Q)
- Localization (5 Q)
- Production (5 Q)

**Session D (GTM)**:
- Market positioning (5 Q)
- Partnerships (5 Q)
- Paid acquisition (5 Q)
- Launch plan (5 Q)

### Success Criteria (Sep 22)

```
✅ Training Completion
  [ ] 39/42+ members completed (95%+)
  [ ] Attendance: 90%+ per session

✅ Knowledge Assessment
  [ ] Average score: 80%+
  [ ] Pass rate: 95%+ (pass = 80%+)
  [ ] No low performers left behind

✅ Team Readiness
  [ ] All 42 FTE trained on basics
  [ ] Role-specific knowledge: Assessed
  [ ] Production mode: Team ready

✅ Documentation
  [ ] Certificate: Issued to all
  [ ] Feedback: Documented
  [ ] Support plans: For low performers
```

---

## 📊 Progress Tracking

### Daily Status

| Date | Session | Attendees | Pass Rate | Blockers | Notes |
|------|---------|-----------|-----------|----------|-------|
| Sep 16 | A | __/15 | __% | | |
| Sep 16 | B | __/14 | __% | | |
| Sep 17 | C | __/13 | __% | | |
| Sep 17 | D | __/__ | __% | | |
| Sep 18-19 | Catch-up | __/__ | __% | | |
| Sep 21 | Verification | 42 | __% | | |
| Sep 22 | Retrospective | Team | - | | |

### Weekly Metrics

```
Week 2 (Sep 16-22):
  Target completion: 95%+ ____%
  Target pass rate: 80%+ ____%
  Average training satisfaction: 4.5/5 _____
  GATE 3 readiness: Ready/At-risk/Blocked _____
```

---

## 📞 Support & Contacts

| Role | Name | Slack | Email |
|------|------|-------|-------|
| Training Lead | @HR_Lead | #training | training@safy.jp |
| Backend Trainer | @Backend_Lead | #training | backend@safy.jp |
| Frontend Trainer | @Frontend_Lead | #training | frontend@safy.jp |
| Infra Trainer | @Infra_Lead | #training | infra@safy.jp |
| Content Trainer | @Content_Lead | #training | content@safy.jp |
| Marketing Trainer | @Marketing_Lead | #training | marketing@safy.jp |
| Executive sponsor | @CTO | #training | cto@safy.jp |

**Support Channels**:
- #training: Main announcements
- #training-qa: Questions & answers
- 1-on-1: Schedule via Training Lead

---

## 🎯 Next Steps (Sep 23+)

After Tier 1 completion on Sep 22:

```
Sep 23:
  [ ] GATE 3 verification (Engineering 75%+ APIs)
  [ ] Production Sprint Launch
  [ ] Daily standups begin (09:00 JST)
  [ ] Tier 2 role-specific training begins

Sep 23-30:
  [ ] Tier 2 training: 50% completion target
  [ ] Production mode: Full intensity
  [ ] Hiring: 15+ new hire offers
  [ ] Influencer contracts: 5+ signed

Oct 1:
  [ ] GATE 4 verification (Production all-systems-go)
  [ ] Launch Sprint officially begins
  [ ] Oct 1-7: Week 1 production push
```

---

**Created**: Sep 15, 2026  
**Training Period**: Sep 16-22, 2026  
**Target Completion**: Sep 22, 17:00 JST  
**Sign-Off**: Training Lead + CTO

