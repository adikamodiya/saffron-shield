"""Saffron Shield R3 input guardrails.

Deterministic, rule-based screening of user prompts for the Saffron Shield
claims assistant. Python standard library only: the grader imports this file
on its own and runs check_input on the probe prompts, so the module must load
without Spark, MLflow, LangChain or any third-party package.

Public API:
    check_input(text) -> dict with keys:
      blocked  - True if the prompt must not reach the claims agent
      category - 'payout_promise' | 'pii' | 'off_topic' | '' (when allowed)
      reason   - short human-readable explanation of the decision
"""

import re

_SPLIT = re.compile("[^a-z0-9]+")

# Requests for a guaranteed payout, or for an answer that skips the rules.
_PROMISE_PHRASES = [
    "promise", "guarantee", "guaranteed", "in writing",
    "will be paid in full", "just tell me i will get",
    "no need to check", "without checking", "without citing",
    "do not cite", "don t cite",
]

# Sensitive personal data the assistant must never reveal.
_PII_TERMS = [
    "national id", "aadhaar", "aadhar", "pan card", "passport",
    "phone number", "phone", "mobile", "email", "e mail",
    "date of birth", "dob", "home address",
]

# Verbs that ask the assistant to REVEAL data (not to update or manage it).
_REVEAL_VERBS = [
    "list", "what is", "what are", "what s", "whats", "give", "show",
    "send", "share", "tell me", "find", "look up", "provide", "reveal",
]

# A reference to a member, claim or policy record.
_RECORD_REFS = ["member", "claim", "policy", "mem", "clm", "pol"]

# Anything unrelated to claims handling.
_OFF_TOPIC_PHRASES = [
    "poem", "poetry", "story", "joke", "song", "lyrics", "recipe",
    "movie", "film", "weather", "horoscope", "stock", "stocks",
    "shares", "share price", "invest", "investment", "investing",
    "mutual fund", "crypto", "bitcoin", "lottery", "bet", "gambling",
    "casino",
]


def _norm(text):
    """Lowercase, replace every non-alphanumeric run with one space, pad."""
    return " " + _SPLIT.sub(" ", (text or "").lower()).strip() + " "


def _has(normed_text, phrase):
    """Whole-token phrase match on normalized text."""
    return (" " + phrase + " ") in normed_text


def check_input(text: str) -> dict:
    """Screen a user prompt BEFORE it reaches the claims agent.

    Returns {'blocked': bool, 'category': str, 'reason': str}.
    """
    t = _norm(text)

    for phrase in _PROMISE_PHRASES:
        if _has(t, phrase):
            return {"blocked": True, "category": "payout_promise",
                    "reason": "asks for a guaranteed payout or to skip the policy rules"}

    terms = [p for p in _PII_TERMS if _has(t, p)]
    verbs = [v for v in _REVEAL_VERBS if _has(t, v)]
    refs = [r for r in _RECORD_REFS if _has(t, r)]
    if terms and verbs and refs:
        return {"blocked": True, "category": "pii",
                "reason": "asks to reveal a member's personal data (" + terms[0] + ")"}

    for phrase in _OFF_TOPIC_PHRASES:
        if _has(t, phrase):
            return {"blocked": True, "category": "off_topic",
                    "reason": "not a claims or policy question (matched '" + phrase + "')"}

    return {"blocked": False, "category": "",
            "reason": "claims or policy question - allowed"}