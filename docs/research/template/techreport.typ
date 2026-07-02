// techreport.typ — a clean single-column technical-report template for the
// xMotion family (institutional/technical-report style, not a conference paper).
//
// Usage:
//   #import "template/techreport.typ": techreport, appendix
//   #show: techreport.with(title: "...", subtitle: "...", ...)

#let techreport(
  title: "",
  subtitle: none,
  org: "xMotion Family",
  authors: (),           // (name, email, affiliation)
  date: none,
  report-number: none,
  version: none,
  status: none,
  abstract: none,        // rendered as "Executive Summary"
  keywords: (),
  running-head: none,    // short title for the running header
  body,
) = {
  let short = if running-head != none { running-head } else { title }

  set document(title: title, author: authors.map(a => a.name))
  set text(font: "New Computer Modern", size: 10.5pt, lang: "en")
  set par(justify: true, leading: 0.62em, spacing: 1.15em)
  set heading(numbering: "1.1")
  show link: underline
  set cite(style: "ieee")

  // Table/figure styling
  set table(stroke: (x, y) => (
    top: if y == 0 { 0.9pt } else { 0pt },
    bottom: 0.5pt,
  ), inset: 6pt)
  show table.cell.where(y: 0): set text(weight: "bold")
  set figure(gap: 0.9em)
  show figure.caption: set text(size: 9pt)

  // Heading styles
  show heading.where(level: 1): it => block(above: 1.5em, below: 0.85em)[
    #set text(size: 14pt, weight: "bold")
    #it
  ]
  show heading.where(level: 2): it => block(above: 1.15em, below: 0.55em)[
    #set text(size: 11.5pt, weight: "bold")
    #it
  ]
  show heading.where(level: 3): it => block(above: 0.95em, below: 0.4em)[
    #set text(size: 10.5pt, weight: "bold", style: "italic")
    #it
  ]

  // ---------------- Title page (no header/footer) ----------------
  let meta = ()
  if report-number != none { meta.push(([Report No.], report-number)) }
  if version != none { meta.push(([Version], version)) }
  if status != none { meta.push(([Status], status)) }
  if date != none { meta.push(([Date], date)) }
  if authors.len() > 0 {
    meta.push(([Prepared by], authors.map(a => a.name).join(", ")))
  }

  page(margin: (x: 28mm, top: 34mm, bottom: 28mm), numbering: none,
       header: none, footer: none)[
    #text(size: 9pt, tracking: 2pt, weight: "medium")[#upper(org) #h(4pt) · #h(4pt) TECHNICAL REPORT]
    #v(3pt)
    #line(length: 100%, stroke: 1.2pt)
    #v(14pt)
    #text(size: 22pt, weight: "bold")[#title]
    #if subtitle != none [
      #v(7pt)
      #text(size: 13pt, fill: rgb("#3a3a3a"))[#subtitle]
    ]
    #v(11pt)
    #line(length: 100%, stroke: 0.6pt)
    #v(1.4em)

    #if meta.len() > 0 [
      #grid(
        columns: (auto, 1fr),
        row-gutter: 6pt,
        column-gutter: 14pt,
        ..meta.map(kv => (
          text(size: 9.5pt, fill: rgb("#555"))[#kv.at(0)],
          text(size: 9.5pt)[#kv.at(1)],
        )).flatten()
      )
    ]

    #if abstract != none [
      #v(1.7em)
      #block(fill: rgb("#f5f5f5"), inset: 13pt, radius: 3pt, width: 100%,
             stroke: 0.5pt + rgb("#dcdcdc"))[
        #text(weight: "bold", size: 10pt, tracking: 0.5pt)[EXECUTIVE SUMMARY]
        #v(5pt)
        #set par(justify: true, leading: 0.6em)
        #set text(size: 9.6pt)
        #abstract
      ]
    ]

    #if keywords.len() > 0 [
      #v(0.9em)
      #text(size: 9pt)[*Keywords* — #keywords.join(" · ")]
    ]
  ]

  // ---------------- Body pages (running header + page numbers) --------
  set page(
    margin: (x: 25mm, top: 26mm, bottom: 24mm),
    numbering: "1",
    number-align: center,
    header: [
      #set text(size: 8pt, fill: rgb("#666"))
      #grid(columns: (1fr, auto))[#smallcaps[#short]][#org]
      #v(-6pt)
      #line(length: 100%, stroke: 0.4pt + rgb("#bbbbbb"))
    ],
  )
  counter(page).update(1)

  outline(title: [Contents], depth: 2, indent: auto)
  pagebreak()

  body
}

// Switch to lettered appendix numbering (A, A.1, ...).
#let appendix(body) = {
  counter(heading).update(0)
  set heading(numbering: "A.1")
  body
}
