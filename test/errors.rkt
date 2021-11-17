#lang racket/base

(require "../main.rkt"
         (for-syntax racket/base syntax/parse)
         syntax/macro-testing
         racket/exn
         rackunit)

;;
;; Helpers
;;

(define ((check-formatted-error-matches rx) exn)
  (regexp-match? rx (exn->string exn)))

(define-syntax-rule (check-decl-error rx decl-stx)
  (check-exn
   (check-formatted-error-matches rx)
   (lambda ()
     (eval-syntax #`(module m racket/base
                      (require "../main.rkt")
                      #,decl-stx)))))

(define-syntax-rule (check-phase1-error rx e)
  (check-exn
   (check-formatted-error-matches rx)
   (lambda () (phase1-eval e #:catch? #t))))

(define-syntax-rule (check-syntax-error rx e)
  (check-exn
   (check-formatted-error-matches rx)
   (lambda () (convert-compile-time-error e))))

;;
;; Nonterminal declaration syntax errors
;;

(check-decl-error
 #rx"nonterminal: expected extension class name"
 #'(define-hosted-syntaxes
     (binding-class var "var")
     (nonterminal expr
                  #:allow-extension unbound-name
                  v:var)))

(check-decl-error
 #rx"nesting-nonterminal: expected pattern variable binding for nested syntax"
 #'(define-hosted-syntaxes
     (nesting-nonterminal binding-group
                          1)))

;;
;; Syntax spec syntax errors
;;

(check-decl-error
 #rx"nonterminal: expected a syntax spec term"
 #'(define-hosted-syntaxes
     (nonterminal expr
                  1)))

(check-decl-error
 #rx"nonterminal: expected a reference to a binding class, syntax class, or nonterminal"
 #'(define-hosted-syntaxes
     (nonterminal expr
                  x:unbound-name)))

(check-decl-error
 #rx"nonterminal: duplicate pattern variable"
 #'(define-hosted-syntaxes
     (binding-class dsl-var "dsl-var")
     (nonterminal expr
                  [x:dsl-var x:dsl-var])))

;;
;; Binding spec syntax errors
;;

(check-decl-error
 #rx"nonterminal: binding spec expected a reference to a pattern variable"
 #'(define-hosted-syntaxes
     (binding-class dsl-var "DSL variable")
     (nonterminal expr
                  x:dsl-var
                  #:binding {y})))

(check-decl-error
 #rx"!: expected a reference to a pattern variable"
 #'(define-hosted-syntaxes
     (binding-class dsl-var "DSL variable")
     (nonterminal expr
                  x:dsl-var
                  #:binding {(! y)})))

(check-decl-error
 #rx"nonterminal: nesting nonterminals may only be used with `nest`"
 #'(define-hosted-syntaxes
     (binding-class dsl-var "DSL variable")
     (nonterminal expr
                  b:binding-group
                  #:binding b)
     (nesting-nonterminal binding-group (nested)
                          [])))

(check-decl-error
 #rx"nest: expected pattern variable associated with a nesting nonterminal"
 #'(define-hosted-syntaxes
     (nonterminal expr
                  (e:expr)
                  #:binding (nest e []))))

(check-decl-error
 #rx"nest: expected more terms starting with binding spec term"
 #'(define-hosted-syntaxes
     (nonterminal expr
                  b:expr
                  #:binding (nest b))))

(check-decl-error
 #rx"!: expected pattern variable associated with a binding class"
 #'(define-hosted-syntaxes
     (nonterminal expr
                  b:expr
                  #:binding (! b))))

(check-decl-error
 #rx"rec: expected pattern variable associated with a two-pass nonterminal"
 #'(define-hosted-syntaxes
     (nonterminal expr
                  b:expr
                  #:binding (rec b))))


(check-decl-error
 #rx"nonterminal: exports may only occur at the top-level of a two-pass binding spec"
 #'(define-hosted-syntaxes
     (binding-class var "var")
     (nonterminal expr
                  v:var
                  #:binding (^ v))))

;;
;; Valid definitions used to exercise errors
;;

(define-hosted-syntaxes
  (binding-class dsl-var "DSL var")
  (nonterminal expr1
               n:number
               v:dsl-var
               [b:dsl-var e:expr1]
               #:binding {(! b) e})
  (nonterminal expr2
               #:description "DSL expression"
               n:number)
  (nesting-nonterminal binding-group (tail)
                       [v:dsl-var e:expr1]
                       #:binding {(! v) tail}))

;;
;; Accessor syntax errors
;;

(check-phase1-error
 #rx"binding-class-constructor: expected a binding class name"
 (binding-class-constructor unbound-name))

(check-phase1-error
 #rx"nonterminal-expander: expected a nonterminal name"
 (nonterminal-expander unbound-name))

(check-phase1-error
 #rx"nonterminal-expander: only simple non-terminals may be used as entry points"
 (nonterminal-expander binding-group))

;;
;; Runtime (wrt the meta-DSL) errors
;;

(define-syntax (dsl-expr1 stx)
  (syntax-parse stx
    [(_ e)
     #`'#,((nonterminal-expander expr1) #'e)]))

(define-syntax (dsl-expr2 stx)
  (syntax-parse stx
    [(_ e)
     #`'#,((nonterminal-expander expr2) #'e)]))

;; the interface macro is named as the syntax raising the error.
(check-syntax-error
 #rx"dsl-expr1: expected expr1"
 (dsl-expr1 (foo)))

(check-syntax-error
 #rx"dsl-expr1: not bound as DSL var"
 (dsl-expr1 foo))

;; in subexpression
(check-syntax-error
 #rx"dsl-expr1: expected expr1"
 (dsl-expr1 [foo (foo)]))

(check-syntax-error
 #rx"dsl-expr1: not bound as DSL var"
 (dsl-expr1 [foo bar]))

;; with description, and no variable case
(check-syntax-error
 #rx"dsl-expr2: expected DSL expression"
 (dsl-expr2 foo))