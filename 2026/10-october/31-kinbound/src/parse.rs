//! The family file: people, the records found for them, and optional rule changes.
//!
//! Every line is checked against a fixed shape, every number against a range, and error messages
//! never repeat the input (only line numbers and what was expected).

use std::collections::HashMap;
use std::fmt;

pub const MAX_BYTES: usize = 64 * 1024;
pub const MAX_LINE: usize = 200;
pub const MAX_PEOPLE: usize = 400;
pub const MAX_RECORDS: usize = 1500;
pub const MIN_YEAR: i64 = 1000;
pub const MAX_YEAR: i64 = 2100;
const MAX_NAME: usize = 60;
const MAX_ID: usize = 24;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InputError {
    pub line: usize,
    pub msg: String,
}

impl InputError {
    fn at(line: usize, msg: impl Into<String>) -> Self {
        Self { line, msg: msg.into() }
    }
}

impl fmt::Display for InputError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.line > 0 {
            write!(f, "line {}: {}", self.line, self.msg)
        } else {
            f.write_str(&self.msg)
        }
    }
}

/// A recorded year or range of years, inclusive at both ends. `None` means open.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Span {
    pub lo: Option<i64>,
    pub hi: Option<i64>,
    pub about: bool,
}

impl Span {
    fn exact(y: i64) -> Self {
        Self {
            lo: Some(y),
            hi: Some(y),
            about: false,
        }
    }

    /// How the span reads in a sentence: "in 1841", "about 1840 (1838-1842)", ...
    #[must_use]
    pub fn phrase(&self) -> String {
        match (self.lo, self.hi) {
            (Some(a), Some(b)) if self.about => format!("about {} ({a}-{b})", i64::midpoint(a, b)),
            (Some(a), Some(b)) if a == b => format!("in {a}"),
            (Some(a), Some(b)) => format!("between {a} and {b}"),
            (None, Some(b)) => format!("in or before {b}"),
            (Some(a), None) => format!("in or after {a}"),
            (None, None) => "at some time".to_string(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Kind {
    Born(Span),
    Died(Span),
    Baptised(i64),
    Buried(i64),
    Census {
        year: i64,
        age: i64,
    },
    Alive(i64),
    /// This person is the mother of the person given.
    Mother(usize),
    Father(usize),
    Married {
        spouse: usize,
        year: i64,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Record {
    pub line: usize,
    pub person: usize,
    pub kind: Kind,
}

/// The rules of thumb every family obeys unless the file says otherwise.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Rules {
    pub mother_age: (i64, i64),
    pub father_age: (i64, i64),
    pub lifespan: i64,
    pub marriage_age: i64,
}

impl Default for Rules {
    fn default() -> Self {
        Self {
            mother_age: (14, 50),
            father_age: (15, 80),
            lifespan: 105,
            marriage_age: 14,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Person {
    pub id: String,
    pub name: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Tree {
    pub title: String,
    pub people: Vec<Person>,
    pub records: Vec<Record>,
    pub rules: Rules,
}

impl Tree {
    #[must_use]
    pub fn find(&self, id: &str) -> Option<usize> {
        self.people.iter().position(|p| p.id == id)
    }
}

fn year(tok: &str, line: usize) -> Result<i64, InputError> {
    if tok.is_empty() || tok.len() > 4 || !tok.bytes().all(|b| b.is_ascii_digit()) {
        return Err(InputError::at(line, "years are written as plain numbers, like 1841"));
    }
    let y: i64 = tok
        .parse()
        .map_err(|_| InputError::at(line, "years are written as plain numbers, like 1841"))?;
    if !(MIN_YEAR..=MAX_YEAR).contains(&y) {
        return Err(InputError::at(
            line,
            format!("years must be between {MIN_YEAR} and {MAX_YEAR}"),
        ));
    }
    Ok(y)
}

fn small(tok: &str, line: usize, what: &str, max: i64) -> Result<i64, InputError> {
    let bad = || InputError::at(line, format!("{what} must be a whole number from 0 to {max}"));
    if tok.is_empty() || tok.len() > 3 || !tok.bytes().all(|b| b.is_ascii_digit()) {
        return Err(bad());
    }
    let v: i64 = tok.parse().map_err(|_| bad())?;
    if v > max {
        return Err(bad());
    }
    Ok(v)
}

/// "1841", "about 1841", "1840-1842", "before 1850", "after 1830".
fn span(toks: &[&str], line: usize) -> Result<Span, InputError> {
    let shape = || InputError::at(line, "write a date as 1841, about 1841, 1840-1842, before 1850 or after 1830");
    match toks {
        [y] if y.contains('-') => {
            let (a, b) = y.split_once('-').ok_or_else(shape)?;
            let (a, b) = (year(a, line)?, year(b, line)?);
            if a > b {
                return Err(InputError::at(line, "a range of years must run from earlier to later"));
            }
            Ok(Span {
                lo: Some(a),
                hi: Some(b),
                about: false,
            })
        }
        [y] => Ok(Span::exact(year(y, line)?)),
        ["about", y] => {
            let y = year(y, line)?;
            Ok(Span {
                lo: Some(y - 2),
                hi: Some(y + 2),
                about: true,
            })
        }
        ["before", y] => Ok(Span {
            lo: None,
            hi: Some(year(y, line)?),
            about: false,
        }),
        ["after", y] => Ok(Span {
            lo: Some(year(y, line)?),
            hi: None,
            about: false,
        }),
        _ => Err(shape()),
    }
}

fn valid_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= MAX_ID
        && id.bytes().next().is_some_and(|b| b.is_ascii_lowercase())
        && id
            .bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'_' || b == b'-')
}

/// Letters (any script), digits, spaces and a little punctuation. No control or direction-changing
/// characters, so a name can't rewrite the terminal or reorder the report.
fn valid_name(name: &str) -> bool {
    let n = name.chars().count();
    (1..=MAX_NAME).contains(&n)
        && name.chars().next().is_some_and(char::is_alphanumeric)
        && name.chars().all(|c| c.is_alphanumeric() || " '.,()-".contains(c))
        && !name
            .chars()
            .any(|c| matches!(c, '\u{200B}'..='\u{200F}' | '\u{202A}'..='\u{202E}' | '\u{2066}'..='\u{2069}'))
}

fn bounded_pair(toks: &[&str], line: usize, what: &str) -> Result<(i64, i64), InputError> {
    match toks {
        [a, b] => {
            let (a, b) = (small(a, line, what, 120)?, small(b, line, what, 120)?);
            if a > b {
                return Err(InputError::at(line, format!("{what}: the smaller number comes first")));
            }
            Ok((a, b))
        }
        _ => Err(InputError::at(line, format!("write it like 'rule {what} 14 50'"))),
    }
}

fn rule(toks: &[&str], rules: &mut Rules, line: usize) -> Result<(), InputError> {
    match toks {
        ["mother-age", rest @ ..] => rules.mother_age = bounded_pair(rest, line, "mother-age")?,
        ["father-age", rest @ ..] => rules.father_age = bounded_pair(rest, line, "father-age")?,
        ["lifespan", n] => rules.lifespan = small(n, line, "lifespan", 120)?.max(1),
        ["marriage-age", n] => rules.marriage_age = small(n, line, "marriage-age", 30)?,
        _ => {
            return Err(InputError::at(
                line,
                "rules are mother-age, father-age, lifespan and marriage-age",
            ))
        }
    }
    Ok(())
}

/// Reads a whole family file.
///
/// # Errors
/// An [`InputError`] naming the first line that doesn't fit, without repeating its text.
pub fn parse(text: &str) -> Result<Tree, InputError> {
    if text.len() > MAX_BYTES {
        return Err(InputError::at(0, "the file is larger than 64 KB"));
    }
    let text = text.strip_prefix('\u{FEFF}').unwrap_or(text);
    let mut tree = Tree {
        title: "My family".into(),
        people: vec![],
        records: vec![],
        rules: Rules::default(),
    };
    let mut ids: HashMap<String, usize> = HashMap::new();
    let mut seen_title = false;

    for (i, raw) in text.lines().enumerate() {
        let n = i + 1;
        if raw.chars().count() > MAX_LINE {
            return Err(InputError::at(n, format!("is longer than {MAX_LINE} characters")));
        }
        if raw.chars().any(|c| c.is_control() && c != '\t' && c != '\r') {
            return Err(InputError::at(n, "contains a control character"));
        }
        let body = raw.split('#').next().unwrap_or("").trim();
        let toks: Vec<&str> = body.split_whitespace().collect();
        let Some((&head, rest)) = toks.split_first() else { continue };

        let who = |id: &str| -> Result<usize, InputError> {
            ids.get(id)
                .copied()
                .ok_or_else(|| InputError::at(n, "uses a person before their 'person' line"))
        };
        let kind_for = |person: usize, kind: Kind| Record { line: n, person, kind };

        let record =
            match (head, rest) {
                ("name", words) if !words.is_empty() => {
                    let title = words.join(" ");
                    if seen_title || !valid_name(&title) {
                        return Err(InputError::at(
                            n,
                            "the title comes once, in letters, digits and spaces (up to 60)",
                        ));
                    }
                    seen_title = true;
                    tree.title = title;
                    None
                }
                ("person", [id, words @ ..]) if !words.is_empty() => {
                    let name = words.join(" ");
                    if !valid_id(id) {
                        return Err(InputError::at(
                            n,
                            "a person's id is lower-case letters, digits, _ or - (up to 24)",
                        ));
                    }
                    if !valid_name(&name) {
                        return Err(InputError::at(
                            n,
                            "names use letters, digits, spaces and ' . , ( ) - (up to 60)",
                        ));
                    }
                    if ids.contains_key(*id) {
                        return Err(InputError::at(n, "that id is already used"));
                    }
                    if tree.people.len() >= MAX_PEOPLE {
                        return Err(InputError::at(n, format!("at most {MAX_PEOPLE} people")));
                    }
                    ids.insert((*id).to_string(), tree.people.len());
                    tree.people.push(Person {
                        id: (*id).to_string(),
                        name,
                    });
                    None
                }
                ("born", [id, date @ ..]) => Some(kind_for(who(id)?, Kind::Born(span(date, n)?))),
                ("died", [id, date @ ..]) => Some(kind_for(who(id)?, Kind::Died(span(date, n)?))),
                ("baptised" | "christened", [id, y]) => Some(kind_for(who(id)?, Kind::Baptised(year(y, n)?))),
                ("buried", [id, y]) => Some(kind_for(who(id)?, Kind::Buried(year(y, n)?))),
                ("alive", [id, y]) => Some(kind_for(who(id)?, Kind::Alive(year(y, n)?))),
                ("census", [id, y, "age", a]) => Some(kind_for(
                    who(id)?,
                    Kind::Census {
                        year: year(y, n)?,
                        age: small(a, n, "a census age", 120)?,
                    },
                )),
                ("mother" | "father", [parent, "of", child]) => {
                    let (p, c) = (who(parent)?, who(child)?);
                    if p == c {
                        return Err(InputError::at(n, "nobody is their own parent"));
                    }
                    Some(kind_for(p, if head == "mother" { Kind::Mother(c) } else { Kind::Father(c) }))
                }
                ("married", [a, b, y]) => {
                    let (a, b) = (who(a)?, who(b)?);
                    if a == b {
                        return Err(InputError::at(n, "a marriage needs two different people"));
                    }
                    Some(kind_for(
                        a,
                        Kind::Married {
                            spouse: b,
                            year: year(y, n)?,
                        },
                    ))
                }
                ("rule", words) => {
                    rule(words, &mut tree.rules, n)?;
                    None
                }
                (
                    "name" | "person" | "born" | "died" | "baptised" | "christened" | "buried" | "alive" | "census" | "mother"
                    | "father" | "married",
                    _,
                ) => {
                    return Err(InputError::at(
                        n,
                        "doesn't have the expected shape (see the README for every kind of line)",
                    ))
                }
                _ => return Err(InputError::at(
                    n,
                    "lines start with name, person, born, died, baptised, buried, census, alive, mother, father, married or rule",
                )),
            };
        if let Some(r) = record {
            if tree.records.len() >= MAX_RECORDS {
                return Err(InputError::at(n, format!("at most {MAX_RECORDS} records")));
            }
            tree.records.push(r);
        }
    }
    if tree.people.is_empty() {
        return Err(InputError::at(0, "the file has no 'person' lines"));
    }
    Ok(tree)
}
