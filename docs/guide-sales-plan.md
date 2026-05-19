# VibeGoGo Guide Sales Plan

## Purpose

Create a practical paid guide for people who cannot write code but want to use Claude Code, Codex, and GitHub to improve products with AI.

The first product should not be a SaaS or installer. It should be a note guide that sells the path:

1. Write what you want in a GitHub Issue
2. Ask Claude Code to work with VibeGoGo
3. Let AI create a GitHub confirmation request
4. Check the screen or behavior yourself
5. Say "merge it" when it looks good

The value is not only VibeGoGo's source code. The value is the beginner-safe workflow around it.

## Target Readers

- People who installed Claude Code for the first time
- People who do not understand GitHub, branches, PRs, or commits
- People who cannot write code but have a product or app they want to improve
- Non-engineer founders, indie makers, small business owners, and creators
- People who want AI to help but are afraid it will break something

## Product Concept

Working title:

**AI Coding Safety Driving Guide for People Who Cannot Write Code**

Alternative title ideas:

- Claude Code guide for people who cannot write code
- VibeGoGo guide for building products with AI
- AI coding starter kit for people who do not understand GitHub

Positioning:

VibeGoGo is not "AI writes everything magically." It is a safety rail for letting AI move product work forward without forcing the user to understand every code detail.

## Sales Format

Initial format:

- Paid note article
- Japanese first
- Practical guide with templates
- Public GitHub repository as the working artifact

Later expansion:

- Template pack
- Individual setup support
- Team onboarding guide
- English version
- Optional video walkthrough

## Pricing

Initial guide:

- 980 to 1,980 JPY
- Recommended first price: 1,480 JPY

Expanded guide with templates:

- 2,980 JPY

Individual setup support:

- 10,000 to 30,000 JPY per session

The first goal is not maximum revenue. The first goal is proof that someone can follow the guide and reach a GitHub confirmation request safely.

## Free Section

The free section should create recognition and trust.

Topics:

- Why AI coding is scary when you cannot read code
- Why "just ask AI" is not enough
- Why GitHub terms like branch, PR, and merge feel confusing
- What can go wrong when AI edits a product without guardrails
- How VibeGoGo turns the work into a simple route:
  - Issue
  - Implementation
  - Confirmation request
  - User checks behavior
  - Merge
- What the user needs to understand, and what they do not need to understand

Free section goal:

The reader should feel: "This problem is about me, and this path might let me try."

## Paid Section

The paid section should be a practical kit, not only an essay.

### 1. The Only Three Words to Learn

Explain these without assuming programming knowledge:

- Issue: the place where you write what you want
- Confirmation request: the place where AI shows the change before it becomes official
- Merge: making the confirmed change official

Keep PR, branch, and commit as technical note words.

### 2. First Workflow

Explain the full route:

1. Write a GitHub Issue
2. Tell Claude Code: "Please handle this Issue with VibeGoGo"
3. AI works and creates a confirmation request
4. You check the screen or behavior
5. If it looks good, say: "merge it"

### 3. GitHub Issue Template

```md
## What I want

Example: Add a dark mode switch to the settings screen.

## Expected behavior

Example: When I turn on the switch, the screen changes to dark colors.

## What I want to check

Example: The setting remains after restarting the app.

## What I do not want changed

Example: Do not change login or billing behavior.
```

### 4. What to Say to Claude Code

Starter prompt:

```text
Please handle this Issue with VibeGoGo.
Do not stop for progress confirmation.
Stop only if a risky change is needed, and explain it in plain language.
```

Merge prompt:

```text
It looks good. Please merge it.
```

Status prompt:

```text
Please explain where we are now in beginner-friendly language.
```

Stop prompt:

```text
Please stop here and explain what has been done so far.
```

### 5. How to Read Completion Reports

Explain the three main endings:

- "Confirmation request created": AI has prepared a change, but it is not official yet
- "Completed": the change is now official on GitHub and local files match
- "Stopped here": AI found a risky decision and needs human judgment

Explain that the "technical note" is for traceability. The user can usually read the top part first.

### 6. What the User Should Check

The user does not need to read code. The user should check behavior:

- Does the screen behave as expected?
- Does the wording feel right?
- Are important existing features still working?
- Is there anything strange or surprising?
- Does the completion report say there is a next action?

### 7. Risky Changes

Explain that VibeGoGo should stop before touching:

- Login
- Permissions
- Billing
- Analytics
- User data
- Data deletion
- External services
- Security-sensitive behavior

Provide plain-language examples of what to ask:

```text
Please explain the risk in simpler words.
```

```text
What happens if we do not make this risky change?
```

```text
Is there a safer smaller change?
```

### 8. Sample Issues

Include at least three initial sample Issues:

1. Change button wording
2. Improve a settings screen explanation
3. Fix a small visible bug

Later add:

4. Add a small UI option
5. Improve README wording
6. Add a simple test

### 9. Troubleshooting Phrases

```text
What should I check on the screen?
```

```text
Are there any risky changes?
```

```text
Please explain without Git terms.
```

```text
Please show only what I need to decide.
```

```text
Please make a smaller safer plan.
```

### 10. Installing VibeGoGo

Keep this practical and short:

- Install Claude Code
- Prepare a GitHub repository
- Copy the VibeGoGo skill
- Register hooks
- Create a first Issue
- Run the first VibeGoGo session

Link to repository setup docs rather than duplicating every technical detail.

## Included Templates

The guide should include:

- GitHub Issue template
- Claude Code starter prompt
- Merge prompt
- Stop prompt
- Beginner-friendly completion report examples
- Risky-change questions
- `.fop-target` examples
- Beginner checklist

## MVP Scope

Include in the first paid note:

- Why this exists
- The three-word vocabulary
- The Issue to confirmation request to merge workflow
- Issue template
- Claude Code prompt templates
- Completion report reading guide
- Three sample Issues
- Basic install and first run guide

Do not include in the first version:

- Video course
- Many screenshots
- Multiple product-specific `.fop-target` variants
- Enterprise/team operations
- English version
- SaaS or CLI installer

## Production Steps

1. Add a GitHub beginner guide to this repository
2. Link it from README
3. Rewrite the beginner guide into a note article
4. Add templates as copy-paste blocks
5. Run one real example from Issue to confirmation request to merge
6. Capture screenshots only where they reduce confusion
7. Publish the first note
8. Share it on X, GitHub, and note
9. Collect questions
10. Improve the guide based on real confusion

## Success Metrics

Do not measure only revenue at first.

Early indicators:

- People understand what VibeGoGo is for
- People say "I might be able to try this"
- Someone writes their first GitHub Issue
- Someone reaches a confirmation request
- Someone says "merge it" with confidence
- The guide pays for part of AI tool costs

Initial revenue target:

- Price: 1,480 JPY
- First-month sales: 10 copies
- Revenue: 14,800 JPY

Medium target:

- Expanded guide: 2,980 JPY
- 30 copies
- 3 individual setup sessions

## Messaging Principles

Do say:

- VibeGoGo is a safety rail
- You do not need to read every line of code
- You still need to check behavior
- Risky changes should stop for human judgment
- The technical note is there for traceability

Do not say:

- Anyone can build any app without engineering knowledge
- AI will make everything safe automatically
- You never need to understand what is happening
- VibeGoGo removes product responsibility

## Next Documentation Work

Create these repository docs:

- `docs/beginner-guide.md`
- `docs/issue-template.md`
- `docs/first-run-checklist.md`

The note article should link back to those GitHub docs.
