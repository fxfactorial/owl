(*
 * OWL - an OCaml numerical library for scientific computing
 * Copyright (c) 2016-2017 Liang Wang <liang.wang@cl.cam.ac.uk>
 *)

module S = Pervasives
module M = Owl_dense_real

type mat = Owl_dense_real.mat

(* type definitions *)

type t =
  | Float of float
  | Matrix of mat
  | DF of t * t * int                            (* primal, tangent, tag *)
  | DR of t * t ref * trace_op * int ref * int   (* primal, adjoint, op, fanout, tag *)
and trace_op =
  | Add_D_D of t * t
  | Add_D_C of t
  | Add_C_D of t
  | Sub_D_D of t * t
  | Sub_D_C of t
  | Sub_C_D of t
  | Mul_D_D of t * t
  | Mul_D_C of t * t
  | Mul_C_D of t * t
  | Div_D_D of t * t
  | Div_D_C of t * t
  | Div_C_D of t * t
  | Sin_D of t
  | Cos_D of t
  | Signum_D of t

let _global_tag = ref 0
let new_tag () = _global_tag := !_global_tag + 1; !_global_tag

(* FIXME *)
let cmp_tag ai bi =
  if ai > bi then 1
  else if ai < bi then -1
  else 0

let make_dual p t i = DF (p, t, i)

let dual = function
  | Float a -> Float 0.
  | Matrix a -> Float 0.
  | DF (_, at, _) -> at

let rec zero = function
  | Float _ -> Float 0.
  | Matrix _ -> Float 0.
  | DF (ap, at, ai) -> DF ((zero ap), (zero at), ai)  (* need to check *)

let rec one = function
  | Float _ -> Float 1.
  | Matrix _ -> failwith "Error: one does not take matrix."
  | DF (ap, at, ai) -> DF ((one ap), (zero at), ai)


(* overload operators *)

module Maths = struct

  let rec noop _ = ()

  and op_d_d a ff fd df r =
    match a with
    | DF (ap, at, ai)      -> let cp = fd ap in DF (cp, (df cp ap at), ai)
    | DR (ap, _, _, _, ai) -> DR (fd ap, ref (Float 0.), r a, ref 0, ai)
    | ap                   -> ff ap

  and op_d_d_d a b ff fd df_da df_db df_dab r_d_d r_d_c r_c_d =
    match a, b with
    | Float ap, DF (bp, bt, bi)                  -> let cp = fd a bp in DF (cp, (df_db cp bp bt), bi)
    | DF (ap, at, ai), Float bp                  -> let cp = fd ap b in DF (cp, (df_da cp ap at), ai)
    | Matrix ap, DF (bp, bt, bi)                 -> let cp = fd a bp in DF (cp, (df_db cp bp bt), bi)
    | DF (ap, at, ai), Matrix bp                 -> let cp = fd ap b in DF (cp, (df_da cp ap at), ai)
    | Float ap, DR (bp, _, _, _, bi)             -> DR (fd a bp, ref (Float 0.), r_c_d a b, ref 0, bi)
    | DR (ap, _, _, _, ai), Float bp             -> DR (fd ap b, ref (Float 0.), r_d_c a b, ref 0, ai)
    | Matrix ap, DR (bp, _, _, _, bi)            -> DR (fd a bp, ref (Float 0.), r_c_d a b, ref 0, bi)
    | DR (ap, _, _, _, ai), Matrix bp            -> DR (fd ap b, ref (Float 0.), r_d_c a b, ref 0, ai)
    | DF (ap, at, ai), DR (bp, _, _, _, bi)      -> (
        match cmp_tag ai bi with
        | 1  -> let cp = fd ap b in DF (cp, df_da cp ap at, ai)
        | -1 -> DR (fd a bp, ref (Float 0.), r_c_d a b, ref 0, bi)
        | _  -> failwith "error: forward and backward clash on the same level"
      )
    | DR (ap, _, _, _, ai), DF (bp, bt, bi)      -> (
        match cmp_tag ai bi with
        | -1 -> let cp = fd a bp in DF (cp, df_db cp bp bt, bi)
        | 1  -> DR (fd ap b, ref (Float 0.), r_d_c a b, ref 0, ai)
        | _  -> failwith "error: forward and backward clash on the same level"
      )
    | DF (ap, at, ai), DF (bp, bt, bi)           -> (
        match cmp_tag ai bi with
        | 0 -> let cp = fd ap bp in DF (cp, (df_dab cp ap at bp bt), ai)
        | 1 -> let cp = fd ap b in DF (cp, (df_da cp ap at), ai)
        | _ -> let cp = fd a bp in DF (cp, (df_db cp bp bt), bi)
      )
    | DR (ap, _, _, _, ai), DR (bp, _, _, _, bi) -> (
        match cmp_tag ai bi with
        | 0 -> DR (fd ap bp, ref (Float 0.), r_d_d a b, ref 0, ai)
        | 1 -> DR(fd ap b, ref (Float 0.), r_d_c a b, ref 0, ai)
        | _ -> DR(fd a bp, ref (Float 0.), r_c_d a b, ref 0, bi)
      )
    | a, b                                       -> ff a b

  and ( +. ) a b = add a b
  and add a b =
    let ff a b =
      match a, b with
      | Float a, Float b   -> Float S.(a +. b)
      | Float a, Matrix b  -> Matrix M.(a $+ b)
      | Matrix a, Float b  -> Matrix M.(a +$ b)
      | Matrix a, Matrix b -> Matrix M.(a +@ b)
    in
    let fd a b = a +. b
    in
    let df_da cp ap at = at
    in
    let df_db cp bp bt = bt
    in
    let df_dab cp ap at bp bt = at +. bt
    in
    let r_d_d a b = Add_D_D (a, b)
    in
    let r_d_c a b = Add_D_C a
    in
    let r_c_d a b = Add_C_D b
    in
    op_d_d_d a b ff fd df_da df_db df_dab r_d_d r_d_c r_c_d

  and ( -. ) a b = sub a b
  and sub a b =
    let ff a b =
      match a, b with
      | Float a, Float b   -> Float S.(a -. b)
      | Float a, Matrix b  -> Matrix M.(a $- b)
      | Matrix a, Float b  -> Matrix M.(a -$ b)
      | Matrix a, Matrix b -> Matrix M.(a -@ b)
    in
    let fd a b = a -. b
    in
    let df_da cp ap at = at
    in
    let df_db cp bp bt = Float 0. -. bt
    in
    let df_dab cp ap at bp bt = at -. bt
    in
    let r_d_d a b = Sub_D_D (a, b)
    in
    let r_d_c a b = Sub_D_C a
    in
    let r_c_d a b = Sub_C_D b
    in
    op_d_d_d a b ff fd df_da df_db df_dab r_d_d r_d_c r_c_d

  and ( *. ) a b = mul a b
  and mul a b =
    let ff a b =
      match a, b with
      | Float a, Float b   -> Float S.(a *. b)
      | Float a, Matrix b  -> Matrix M.(a $* b)
      | Matrix a, Float b  -> Matrix M.(a *$ b)
      | Matrix a, Matrix b -> Matrix M.(a *@ b)
    in
    let fd a b = a *. b
    in
    let df_da cp ap at = at *. b
    in
    let df_db cp bp bt = a *. bt
    in
    let df_dab cp ap at bp bt = (ap *. bt) +. (at *. bp)
    in
    let r_d_d a b = Mul_D_D (a, b)
    in
    let r_d_c a b = Mul_D_C (a, b)
    in
    let r_c_d a b = Mul_C_D (a, b)
    in
    op_d_d_d a b ff fd df_da df_db df_dab r_d_d r_d_c r_c_d

  and ( /. ) a b = div a b
  and div a b =
    let ff a b =
      match a, b with
      | Float a, Float b   -> Float S.(a /. b)
      | Float a, Matrix b  -> Matrix M.(a $/ b)
      | Matrix a, Float b  -> Matrix M.(a /$ b)
      | Matrix a, Matrix b -> Matrix M.(a /@ b)
    in
    let fd a b = a /. b
    in
    let df_da cp ap at = at /. b
    in
    let df_db cp bp bt = (Float 0.) -. (bt *. cp /. bp)
    in
    let df_dab cp ap at bp bt = (at -. bt *. cp) /. bp
    in
    let r_d_d a b = Div_D_D (a, b)
    in
    let r_d_c a b = Div_D_C (a, b)
    in
    let r_c_d a b = Div_C_D (a, b)
    in
    op_d_d_d a b ff fd df_da df_db df_dab r_d_d r_d_c r_c_d

  and signum a =
    let ff = function
      | Float a -> Float Owl_maths.(signum a)
      | Matrix a -> Matrix M.(signum a)
    in
    let fd a = signum a
    in
    let df cp ap at = zero ap
    in
    let r a = Signum_D a
    in
    op_d_d a ff fd df r

  and sin a =
    let ff = function
      | Float a -> Float S.(sin a)
      | Matrix a -> Matrix M.(sin a)
    in
    let fd a = sin a
    in
    let df cp ap at = at *. cos ap
    in
    let r a = Sin_D a
    in
    op_d_d a ff fd df r

  and cos a =
    let ff = function
      | Float a -> Float S.(cos a)
      | Matrix a -> Matrix M.(cos a)
    in
    let fd a = cos a
    in
    let df cp ap at = Float 0. -. (at *. sin ap)
    in
    let r a = Cos_D a
    in
    op_d_d a ff fd df r

end


(* wrappers *)

let diff f = fun x ->
  let x = make_dual x (one x) (new_tag ()) in
  f x |> dual