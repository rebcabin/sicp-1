; from ch3.scm
(define (add-streams s1 s2)
  (stream-map + s1 s2))