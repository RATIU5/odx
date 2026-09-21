package odx

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:os"
import "core:slice"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

// `odx ask "<question>"` (10b, 10c, 17.18): BM25 over the rulebook, no network, no cache.
// The model never writes rule content; it gets topic ids and the rules behind them.
// The index is a few hundred tokens and rebuilds in microseconds, so it is not persisted.

Doc :: struct {
	topic: ^Topic,
	tf:    map[string]f64, // term -> weighted count (tags, aliases, example questions x3)
	len:   f64,
}

Hit :: struct {
	topic: ^Topic,
	score: f64,
}

BM25_K1 :: 1.2
BM25_B :: 0.75
TAG_BOOST :: 3.0
ASK_TOP :: 3
EVAL_FILE :: "rules/ask-eval.json5"
EVAL_MIN_RECALL :: 0.9 // below this the plan says to add a router (10b)

// Lucene's ENGLISH_STOP_WORDS_SET (33 words, Apache-2.0) minus if/or/no/not, which rules
// mention as keywords. BM25's idf already down-weights anything else that is common.
STOPWORDS := []string {
	"a",
	"an",
	"and",
	"are",
	"as",
	"at",
	"be",
	"but",
	"by",
	"for",
	"in",
	"into",
	"is",
	"it",
	"of",
	"on",
	"such",
	"that",
	"the",
	"their",
	"then",
	"there",
	"these",
	"they",
	"this",
	"to",
	"was",
	"will",
	"with",
}

cmd_ask :: proc(o: Opts) {
	p := must_load(o, false)
	if o.eval {
		os.exit(run_eval(&p))
	}
	if len(o.args) !=
	   1 {fail("usage: odx ask \"<question>\" [--explain] [--json] | odx ask --eval")}
	q := tokenize(o.args[0])
	if len(q) ==
	   0 {fail("the question has no searchable words (stopwords and punctuation are dropped)")}
	hits := search(&p.rb, q, ASK_TOP)
	if o.json {
		Out :: struct {
			topic: string,
			score: f64,
			rules: []Rule,
		}
		out := make([dynamic]Out, context.temp_allocator)
		for h in hits {append(&out, Out{h.topic.name, h.score, h.topic.rules})}
		print_json(out[:])
		return
	}
	if len(hits) == 0 {
		fmt.println("no topic matches; try `odx topics`")
		os.exit(EXIT_VIOLATION)
	}
	fmt.printfln("local match (terms: %s)", strings.join(q, " ", context.temp_allocator))
	for h in hits {
		if o.explain {fmt.printf("%.2f\t", h.score)}
		fmt.printfln("%s: %s", h.topic.name, h.topic.summary)
		for r in h.topic.rules {
			if r.retired {continue}
			fmt.printfln("  %s/%-3s %s", h.topic.name, r.id, r.statement)
		}
	}
	fmt.printfln("\nnext: odx explain %s", hits[0].topic.name)
}

// build_index turns every topic into a bag of stemmed terms with per-field weights.
build_index :: proc(rb: ^Rulebook) -> []Doc {
	docs := make([]Doc, len(rb.topics), context.temp_allocator)
	for &t, i in rb.topics {
		d := &docs[i]
		d.topic = &t
		d.tf = make(map[string]f64, context.temp_allocator)
		add_terms(d, t.name, TAG_BOOST)
		for s in t.tags {add_terms(d, s, TAG_BOOST)}
		for s in t.aliases {add_terms(d, s, TAG_BOOST)}
		for s in t.example_questions {add_terms(d, s, TAG_BOOST)}
		add_terms(d, t.summary, 1)
		for r in t.rules {
			if r.retired {continue}
			add_terms(d, r.statement, 1)
			add_terms(d, r.why, 1)
			add_terms(d, r.class, 1)
		}
		for _, n in d.tf {d.len += n}
	}
	return docs
}

@(private = "file")
add_terms :: proc(d: ^Doc, text: string, weight: f64) {
	for term in tokenize(text) {d.tf[term] += weight}
}

// search ranks topics by BM25 and returns the top k with a positive score.
search :: proc(rb: ^Rulebook, query: []string, k: int) -> []Hit {
	docs := build_index(rb)
	n := f64(len(docs))
	avg := 0.0
	for d in docs {avg += d.len}
	avg /= max(n, 1)
	terms := slice.clone(query, context.temp_allocator)
	slice.sort(terms)
	terms = slice.unique(terms)
	hits := make([dynamic]Hit)
	for &d in docs {
		score := 0.0
		for term in terms {
			tf := d.tf[term]
			if tf == 0 {continue}
			df := 0.0
			for other in docs {if other.tf[term] > 0 {df += 1}}
			idf := math.ln((n - df + 0.5) / (df + 0.5) + 1)
			score +=
				idf * (tf * (BM25_K1 + 1)) / (tf + BM25_K1 * (1 - BM25_B + BM25_B * d.len / avg))
		}
		if score > 0 {append(&hits, Hit{d.topic, score})}
	}
	slice.sort_by(hits[:], proc(a, b: Hit) -> bool {return a.score > b.score})
	return hits[:min(k, len(hits))]
}

// tokenize (17.18): words are runs of letters, digits and `_`. Each word splits into subtokens
// at `_`, at lower->Upper and at ALLCAPS->Capitalized boundaries (Samurai / word_delimiter
// baseline: `HTTPServer` -> http, server) and letter<->digit edges; a word that split also
// emits itself whole, so an exact identifier query outranks partial matches. Lowercased,
// stopwords dropped, stemmed.
tokenize :: proc(text: string) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	words := strings.fields_proc(
		text,
		proc(r: rune) -> bool {return !(unicode.is_letter(r) || unicode.is_digit(r) || r == '_')},
		context.temp_allocator,
	)
	for word in words {
		parts := split_identifier(word)
		for part in parts {emit(&out, part)}
		if len(parts) > 1 {emit(&out, word)}
	}
	return out[:]
}

@(private = "file")
emit :: proc(out: ^[dynamic]string, raw: string) {
	w := strings.to_lower(raw, context.temp_allocator)
	if len(w) < 2 || slice.contains(STOPWORDS, w) {return}
	append(out, stem(w))
}

// split_identifier: `builder_init` -> builder, init; `XMLParser2` -> XML, Parser, 2.
@(private = "file")
split_identifier :: proc(word: string) -> []string {
	parts := make([dynamic]string, context.temp_allocator)
	rs := utf8.string_to_runes(word, context.temp_allocator)
	start := 0
	for i in 1 ..= len(rs) {
		boundary := i == len(rs)
		if !boundary {
			prev, cur := rs[i - 1], rs[i]
			next: rune = rs[i + 1] if i + 1 < len(rs) else 0
			switch {
			case cur == '_':
				boundary = true
			case prev == '_':
				start = i
			case unicode.is_upper(cur) && unicode.is_lower(prev):
				boundary = true
			case unicode.is_upper(cur) && unicode.is_upper(prev) && unicode.is_lower(next):
				boundary = true
			case unicode.is_digit(cur) != unicode.is_digit(prev):
				boundary = true
			}
		}
		if boundary {
			if i >
			   start {append(&parts, utf8.runes_to_string(rs[start:i], context.temp_allocator))}
			start = i + 1 if i < len(rs) && rs[i] == '_' else i
		}
	}
	return parts[:]
}

// stem: inflection only (Porter steps 1a and 1b). Derivational stripping (Porter 2-5)
// over-stems technical terms (operate/operator/operation collapse) and Harman 1991 found no
// gain from it on short computing abstracts; plurals plus -ing/-ed carry the recall.
@(private = "file")
stem :: proc(w: string) -> string {
	w := w
	switch {
	case strings.has_suffix(w, "sses"):
		w = w[:len(w) - 2]
	case strings.has_suffix(w, "ies"):
		w = w[:len(w) - 2]
	case strings.has_suffix(w, "ss"):
	case strings.has_suffix(w, "s"):
		w = w[:len(w) - 1]
	}
	for suf in ([]string{"ing", "ed"}) {
		if !strings.has_suffix(w, suf) || len(w) - len(suf) < 4 {continue}
		w = w[:len(w) - len(suf)]
		n := len(w)
		switch {
		case strings.has_suffix(w, "at") ||
		     strings.has_suffix(w, "bl") ||
		     strings.has_suffix(w, "iz"):
			w = strings.concatenate({w, "e"}, context.temp_allocator) // allocat -> allocate
		case w[n - 1] == w[n - 2] && !strings.contains_rune("lsz", rune(w[n - 1])):
			w = w[:n - 1] // hopp -> hop
		}
		break
	}
	return w
}

// run_eval (10b): recall@3 and MRR over rules/ask-eval.json5; exit 1 below EVAL_MIN_RECALL so
// tag and summary edits cannot silently degrade retrieval.
run_eval :: proc(p: ^Project) -> int {
	Case :: struct {
		q:            string,
		expected_ids: []string,
	}
	root := p.root if p.root != "" else "."
	data, rerr := os.read_entire_file(join({root, EVAL_FILE}), context.allocator)
	if rerr != nil {fail("%s: cannot read (run from the odx repo)", EVAL_FILE)}
	cases: []Case
	if uerr := json.unmarshal(data, &cases, spec = .JSON5);
	   uerr != nil {fail("%s: %v", EVAL_FILE, uerr)}
	hits_at_3, rr := 0.0, 0.0
	for c in cases {
		ranked := search(&p.rb, tokenize(c.q), ASK_TOP)
		rank := 0
		for h, i in ranked {
			if slice.contains(c.expected_ids, h.topic.name) {
				rank = i + 1
				break
			}
		}
		if rank > 0 {
			hits_at_3 += 1
			rr += 1 / f64(rank)
		} else {
			got := make([dynamic]string, context.temp_allocator)
			for h in ranked {append(&got, h.topic.name)}
			fmt.printfln("miss: %q wanted %v got %v", c.q, c.expected_ids, got[:])
		}
	}
	n := f64(len(cases))
	recall := hits_at_3 / n
	fmt.printfln(
		"ask eval: %d questions, recall@3 %.2f, MRR %.2f (local only)",
		len(cases),
		recall,
		rr / n,
	)
	return 0 if recall >= EVAL_MIN_RECALL else EXIT_VIOLATION
}
