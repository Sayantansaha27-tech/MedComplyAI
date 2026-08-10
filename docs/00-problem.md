# The problem

*In the customer's words. No technology in this document.*

---

A regulatory affairs consultant is handed a product dossier and asked a
deceptively simple question: **is this ready to file?**

Answering it means reading. A Risk Management File runs to a few hundred pages. A
Company Core Data Sheet, an EU SmPC, an Instructions for Use, a set of standard
operating procedures, and the clinical evaluation each add more. The consultant
reads all of it against a standard, and the standard is itself a document of
requirements written in careful, deliberately general language.

The work is cross-referencing. ISO 14971 requires that every identified hazard
has a corresponding risk control, and that every risk control has verification
evidence. Nobody writes a document that says "here is hazard 7, here is its
control, here is the verification". The hazard is in section 5 of one file, the
control is in an appendix of another, and the verification lives in a test report
that may not be in the dossier at all.

So the consultant builds the map by hand. A spreadsheet, one row per requirement,
filled in by reading. It takes **four to five days** per product.

## Why it takes that long

**Absence is the finding.** Confirming a requirement is *met* means finding the
evidence. Confirming it is *not met* means reading everything and finding
nothing, then being confident enough about the nothing to write it down. The
second is far slower and it is most of the work.

**The same word means different things.** "Risk" appears on nearly every page of
a pharmaceutical dossier. Commercial risk, project risk, and the specific
technical meaning it carries inside a risk management standard are entirely
different, and only a reader who knows the standard can tell them apart.

**Everything must be defensible.** The output is not an opinion. In an
inspection, "we assessed this as adequate" is not an answer. The answer has to be
"section 4.3 of this document, this paragraph, and here is why it satisfies that
clause". Every conclusion needs its evidence attached.

**It repeats.** The document changes and the map is rebuilt. A new market means
the same dossier against a different regulator's requirements. A minor labeling
update means re-checking whether anything downstream became inconsistent.

## What that costs

Four to five days of senior time per review, and the review is a bottleneck: it
happens near the end, when a slip is most expensive. Consultants price it as a
fixed engagement, so overruns come out of margin. Clients experience it as dead
time before they learn whether they can proceed.

And it does not scale. Doubling throughput means hiring another person who
already knows the standards, and those people are scarce and expensive.

## The constraint that rules out the obvious answer

The obvious answer in 2026 is to have an AI read the documents.

These documents cannot leave the building. They are unreleased product
formulations, clinical data, and regulatory strategy. Customers operate under 21
CFR Part 11 and internal governance that prohibit sending this material to a
third-party API. Several are contractually barred by their own clients.

"We will not store your data" is not sufficient. The requirement is that the
documents never transit to someone else's infrastructure at all.

## The second constraint

Even with that solved, a system that produces plausible summaries is not useful
here.

If a tool says a requirement is met, the consultant still has to verify it, which
is the work they were trying to avoid. If it is confidently wrong, it is worse
than nothing, because it invites a signature on a conclusion nobody checked. A
tool that is right most of the time and cannot tell you which times is not a tool
a professional can put their name behind.

What is needed is a system whose reasoning can be audited: one that shows which
sections it searched, which text it found, and why that text does or does not
satisfy a clause. The consultant's job shifts from *finding* the evidence to
*reviewing* the evidence that was found, which is a far faster job and one they
are qualified to do quickly.

## What good looks like

The same review, with the same defensibility, in **four to five hours** instead
of four to five days. Every conclusion carrying its evidence. Nothing leaving the
customer's environment. And the final judgement still made by the qualified human
who signs it.
