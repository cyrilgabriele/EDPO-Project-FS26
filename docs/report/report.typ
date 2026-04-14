#import "@preview/gallus-hsg:1.0.1": *
#import "./metadata.typ": *
#import "@preview/codly:1.3.0": *
#import "@preview/codly-languages:0.1.8": *

#show: codly-init.with()
#codly(
  languages: codly-languages,
  radius: 0.5em,
)

#set document(title: title, author: author)

#show: thesis.with(
  language: language,
  title: title,
  subtitle: subtitle,
  type: type,
  professor: professor,
  author: author,
  matriculation-number: matriculation-number,
  submission-date: submission-date,
  abstract: include "./content/abstract.typ",
  // acknowledgement: include "./content/acknowledgement.typ",
  writing-aids-directory: include "./content/writing-aids-directory.typ",
  // appendix: include "./content/appendix.typ",
)

#include "./content/chapters/project-description.typ"

#pagebreak()
#include "./content/chapters/team-responsibilities.typ"

#pagebreak()
#include "./content/chapters/concepts.typ"

#pagebreak()
#include "./content/chapters/architecture.typ"

#pagebreak()
#include "./content/chapters/adrs.typ"

#pagebreak()
#include "./content/chapters/results.typ"

#pagebreak()
#include "./content/chapters/demonstration.typ"

#pagebreak()
#include "./content/chapters/lessons-learned.typ"
