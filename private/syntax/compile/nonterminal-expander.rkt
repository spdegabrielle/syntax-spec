#lang racket/base

(provide compile-nonterminal-expander)
  
(require racket/base
         syntax/parse
         syntax/id-table
         ee-lib
         "../syntax-classes.rkt"
         "../env-reps.rkt"
         "syntax-spec.rkt"
         "binding-spec.rkt"

         (for-template racket/base
                       "../../runtime/binding-spec.rkt"
                       "pattern-var-reflection.rkt"
                       syntax/parse
                       ee-lib))

(define (compile-nonterminal-expander stx)
  (syntax-parse stx
    [(#:description description
      #:allow-extension (extclass ...)
      #:nested-id #f
      (prod:production-spec) ...)
     (with-syntax ([prod-clauses (map generate-prod-clause (attribute prod.sspec) (attribute prod.bspec))]
                   [macro-clauses (for/list ([extclass (attribute extclass)])
                                    (generate-macro-clause extclass #'recur))])
       #'(lambda (stx-a)
           (let recur ([stx stx-a])
             (syntax-parse stx
               (~@ . macro-clauses)
               (~@ . prod-clauses)
               [_ (raise-syntax-error
                   #f
                   (string-append "not a " (#%datum . description))
                   this-syntax)]))))]
    [(#:description description
      #:allow-extension (extclass ...)
      #:nested-id nested-id:id
      (prod:production-spec) ...)
     (with-syntax ([prod-clauses (map (lambda (sspec bspec) (generate-prod-clause sspec bspec #'nested-id))
                                      (attribute prod.sspec) (attribute prod.bspec))]
                   [macro-clauses (for/list ([extclass (attribute extclass)])
                                    (generate-macro-clause extclass #'recur))])
       #'(lambda (stx-a k)
           (let recur ([stx stx-a])
             (syntax-parse stx
               (~@ . macro-clauses)
               (~@ . prod-clauses)
               [_ (raise-syntax-error
                   #f
                   (string-append "not a " (#%datum . description))
                   this-syntax)]))))]))

(define (generate-prod-clause sspec bspec [nested-id #f])
  (define spec-varmap (sspec-varmap sspec))
  (define varmap (if nested-id
                     (bound-id-table-set spec-varmap nested-id (continuation-binding #'k))
                     spec-varmap))
  
  (with-syntax ([(v ...) (bound-id-table-keys spec-varmap)]
                [pattern (compile-sspec-to-pattern sspec)]
                [bspec-e (compile-bspec bspec varmap)]
                [template (compile-sspec-to-template sspec)])
    #'[pattern
       (let* ([in (hash (~@ 'v (pattern-var-value v)) ...)]
              [out (simple-expand bspec-e in)])
         (rebind-pattern-vars
          (v ...)
          (values (hash-ref out 'v) ...)
          #'template))]))

(define (generate-macro-clause extclass recur-id)
  (let ([ext-info (lookup extclass extclass-rep?)])
    (when (not ext-info)
      (raise-syntax-error #f "not bound as extension class" extclass))
        
    (with-syntax ([m-pred (extclass-rep-pred ext-info)]
                  [m-acc (extclass-rep-acc ext-info)]
                  [recur recur-id])
      #'[(~or m:id (m:id . _))
         #:do [(define binding (lookup #'m m-pred))]
         #:when binding
         (recur (apply-as-transformer (m-acc binding)
                                      #'m
                                      'definition
                                      this-syntax))])))