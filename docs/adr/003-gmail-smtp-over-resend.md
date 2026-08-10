# ADR-003: Gmail SMTP Over Resend

**Date:** 2026-08-01  
**Status:** Accepted

## Context

The API needs to send transactional emails (admin notifications for new submissions, verification status updates, etc.). We evaluated two options:

1. **Resend** — modern email API, but requires a verified custom domain and DNS configuration.
2. **Gmail SMTP via Nodemailer** — send directly from a Gmail account using an App Password.

We want to send emails from `vitacasahealthindia@gmail.com` without purchasing or configuring a custom domain.

## Decision

We will use Nodemailer with Gmail SMTP and a Gmail App Password for all transactional emails.

Configuration:
- SMTP Host: `smtp.gmail.com`
- SMTP Port: 587 (STARTTLS)
- Authentication: Gmail App Password (requires 2-Step Verification on the account)

## Consequences

**Positive:**
- No custom domain required — works immediately with a Gmail account
- Zero cost for email sending
- Simple setup (App Password + Nodemailer)
- Emails appear from the recognizable `vitacasahealthindia@gmail.com` address

**Negative:**
- Gmail imposes a 500 emails/day sending limit (sufficient for V1 with fewer than 500 caregivers)
- Less professional than a custom domain (e.g., `noreply@vitacasa.health`)
- Gmail may rate-limit or flag the account if sending patterns look suspicious
- Must upgrade to Resend, AWS SES, or similar if email volume exceeds 500/day in future versions
