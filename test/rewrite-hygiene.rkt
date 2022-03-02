#lang racket/base

(require "../testing.rkt"
         (for-syntax racket/base ee-lib syntax/parse))

(define-hosted-syntaxes
  (binding-class dsl-name)
  (nonterminal dsl-expr       
    n:dsl-name
    
    (dsl-let n:dsl-name e:dsl-expr)
    #:binding {(bind n) e}

    ;; Introduce binding; need to ensure it does not capture references in e...
    (~> ((~datum a) e)
        #'(dsl-let x e))

    ;; ... particularly references introduced by another ~>.
    (~> ((~datum b))
        #'(dsl-let x (a x)))))

(check-equal?
 (phase1-eval
  (syntax-case ((nonterminal-expander dsl-expr) #'(b)) (dsl-let)
    [(dsl-let b1 (dsl-let b2 r))
     (list (same-binding? #'b1 #'r) (same-binding? #'b2 #'r))]))
 (list #t #f))
