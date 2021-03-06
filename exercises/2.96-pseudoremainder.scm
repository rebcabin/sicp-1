(load "2.87-91-polynomial-algebra.scm")
(load "2.95-troubleshooting.scm")       ; to re-run test with new gcd

(define (test-2.96)

    (display "\n\nOld gcd version: ")
    (test-2.95 'gcd-2.94)

    (display "\n\nIntermediate version (2.96a): ")
    (test-2.95 'gcd-2.96a)
    
    (display "\n\nFinal version (2.96b): ")
    (test-2.95 'gcd)
)

(test-2.96)
