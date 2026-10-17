#import "@preview/mannot:0.4.0": markhl
#set math.equation(numbering: "(1)")
= Structured mathematical composition

// The energy identity keeps the PDE's original mathematical structure.
$ overbracket(integral_(Sigma_1) {
    [(partial_t u)^2 + chevron.l d_x u comma d_x u chevron.r] (N_t)_(Sigma_1)
    - 2 partial_t u thin frac(partial u, partial nu_x) thin norm(N_x)
  } thick d S, "energy flux on future boundary") \
  = underbracket(integral_(Sigma_0) {
    [(partial_t u)^2 + chevron.l d_x u comma d_x u chevron.r] (N_t)_(Sigma_1)
    + 2 partial_t u thin frac(partial u, partial nu_x) thin norm(N_x)
  } thick d S, "energy flux on past boundary") $ <energy-frame>

$ P_y^((n)) (x) = frac(Gamma(frac(n+1,2)), pi^frac(n+1,2))
  frac(y, (y^2 + |x-z|^2)^frac(n+1,2)) $ <fraction-frame>

$ H = integral sqrt(2 (E - V - frac(L^2, 2 r^2))) + G(E,L) $ <root-frame>

$ [cal(F)]_((0,2)) = mat(
  0, -E_1, -E_2, -E_3;
  E_1, 0, B_3, -B_2;
  E_2, -B_3, 0, B_1;
  E_3, B_2, -B_1, 0) $ <matrix-frame>

$ A = underbrace(markhl(a+b+c+d+e+f+g+h+i+j+k+l, color: #yellow),
  "every marked term remains visible") $ <marked-frame>

$ d V_h = sqrt(|op("det")(h_(mu nu))|) d x^0 d x^1 d x^2 d x^3 $ <product-frame>

$ overline(a+b+c+d+e+f+g+h+i+j+k+l) = z $ <bar-frame>

#block[Style controls: $E_1 + z + frac(1,2)$ and $sum_(j=1)^n a_j$.] <style-control>

#link(<energy-frame>)[Energy], #link(<fraction-frame>)[fraction],
#link(<root-frame>)[root], #link(<matrix-frame>)[matrix],
#link(<marked-frame>)[marked terms], #link(<product-frame>)[product],
#link(<bar-frame>)[overline].
