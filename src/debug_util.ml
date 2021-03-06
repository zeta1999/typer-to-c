(*
 *      Typer Compiler
 *
 * ---------------------------------------------------------------------------
 *
 *      Copyright (C) 2011-2016  Free Software Foundation, Inc.
 *
 *   Author: Pierre Delaunay <pierre.delaunay@hec.ca>
 *   Keywords: languages, lisp, dependent types.
 *
 *   This file is part of Typer.
 *
 *   Typer is free software; you can redistribute it and/or modify it under the
 *   terms of the GNU General Public License as published by the Free Software
 *   Foundation, either version 3 of the License, or (at your option) any
 *   later version.
 *
 *   Typer is distributed in the hope that it will be useful, but WITHOUT ANY
 *   WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 *   FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
 *   more details.
 *
 *   You should have received a copy of the GNU General Public License along
 *   with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * ---------------------------------------------------------------------------
 *
 *      Description:
 *          print out each compilation' steps
 *
 * --------------------------------------------------------------------------- *)

(* Utilities *)
open Util
open Fmt
open Debug

(* ASTs *)
open Sexp
open Pexp
open Lexp

(* AST reader *)
open Prelexer
open Lexer
open Lparse
open Eval
module EL = Elexp
module OL = Opslexp

(* definitions *)
open Grammar
open Builtin

(* environments *)
open Debruijn
open Env

let dloc = dummy_location
let dummy_decl = Imm(String(dloc, "Dummy"))

let discard v = ()

(*          Argument parsing        *)
let arg_print_options = ref SMap.empty
let arg_files = ref []
let debug_arg = ref 0

let add_p_option name () =
    debug_arg := (!debug_arg) + 1;
    arg_print_options := SMap.add name true (!arg_print_options)

let get_p_option name =
    try let _ = SMap.find name (!arg_print_options) in
        true
    with
        Not_found -> false

(*
    pretty ?        (print with new lines and indents)
    indent level
    print_type?     (print inferred Type)
    print_index     (print dbi index)
    separate decl   (print extra newline between declarations)
    indent size      4
    highlight       (use console color to display hints)
*)

let _format_mode = ref false
let _ppctx  = ref pretty_ppctx
let _format_dest = ref ""
let _write_file = ref false
let _typecheck = ref false


let _set_print_pretty ctx v =
  ctx := SMap.add "pretty" (Bool (v)) !ctx

let _set_print_type ctx v =
  ctx := SMap.add "print_type" (Bool (v)) !ctx

let _set_print_index ctx v =
  ctx := SMap.add "print_dbi" (Bool (v)) !ctx

let _set_print_indent_size ctx v =
  ctx := SMap.add "indent_size" (Int (v)) !ctx

let _set_highlight ctx v =
  ctx := SMap.add "color" (Bool (v))!ctx

let mod_ctx f v = f _ppctx v; f debug_ppctx v

let set_print_type v () = mod_ctx _set_print_type v
let set_print_index v () = mod_ctx _set_print_index v
let set_print_indent_size v =  mod_ctx _set_print_indent_size v
let set_highlight v () =  mod_ctx _set_highlight v
let set_print_pretty v () = mod_ctx _set_print_pretty v
let set_typecheck v ()    = _typecheck := v

let output_to_file str =
    _write_file := true;
    _format_dest := str;
    set_highlight false ()


let arg_defs = [
    (* format *)
    ("--format",
        Arg.Unit (fun () -> _format_mode := true), " format a typer source code");
    ("-fmt-type=on",
        Arg.Unit (set_print_type true), " Print type info");
    ("-fmt-pretty=on",
        Arg.Unit (set_print_pretty true), " Print with indentation");
    ("-fmt-pretty=off",
        Arg.Unit (set_print_pretty false), " Print expression in one line");
    ("-fmt-type=off",
        Arg.Unit (set_print_type false), " Don't print type info");
    ("-fmt-index=on",
        Arg.Unit (set_print_index true), " Print DBI index");
    ("-fmt-index=off",
        Arg.Unit (set_print_index false), " Don't print DBI index");
    ("-fmt-indent-size",
        Arg.Int set_print_indent_size, " Indent size");
    ("-fmt-highlight=on",
        Arg.Unit (set_highlight true), " Enable Highlighting for typer code");
    ("-fmt-highlight=off",
        Arg.Unit (set_highlight false), " Disable Highlighting for typer code");
    ("-fmt-file",
        Arg.String output_to_file, " Output formatted code to a file");

    ("-typecheck",
        Arg.Unit (add_p_option "typecheck"), " Enable type checking");

    (*  Debug *)
    ("-pretok",
        Arg.Unit (add_p_option "pretok"), " Print pretok debug info");
    ("-tok",
        Arg.Unit (add_p_option "tok"), " Print tok debug info");
    ("-sexp",
        Arg.Unit (add_p_option "sexp"), " Print sexp debug info");
    ("-pexp",
        Arg.Unit (add_p_option "pexp"), " Print pexp debug info");
    ("-lexp",
        Arg.Unit (add_p_option "lexp"), " Print lexp debug info");
    ("-lctx",
        Arg.Unit (add_p_option "lctx"), " Print lexp context");
    ("-rctx",
        Arg.Unit (add_p_option "rctx"), " Print runtime context");
    ("-all",
        Arg.Unit (fun () ->
            add_p_option "pretok" ();
            add_p_option "tok" ();
            add_p_option "sexp" ();
            add_p_option "pexp" ();
            add_p_option "lexp" ();
            add_p_option "lctx" ();
            add_p_option "rctx" ();),
        " Print all debug info");
]

let parse_args () =
  Arg.parse arg_defs (fun s -> arg_files:= s::!arg_files) ""

let make_default () =
    arg_print_options := SMap.empty;
    add_p_option "sexp" ();
    add_p_option "pexp" ();
    add_p_option "lexp" ()


let format_source () =
    print_string (make_title " ERRORS ");

    let filename = List.hd (!arg_files) in
    let pretoks = prelex_file filename in
    let toks = lex default_stt pretoks in
    let nodes = sexp_parse_all_to_list default_grammar toks (Some ";") in
    let pexps = pexp_decls_all nodes in
    let ctx = default_ectx in
    let lexps, _ = lexp_p_decls pexps ctx in

    print_string (make_sep '-'); print_string "\n";

    let result = _lexp_str_decls (!_ppctx) (List.flatten lexps) in

    if (!_write_file) then (
        print_string ("    " ^ " Writing output file: " ^ (!_format_dest) ^ "\n");
        let file = open_out (!_format_dest) in

        List.iter (fun str -> output_string file str) result;

        flush_all ();
        close_out file;

    ) else (List.iter (fun str ->
        print_string str; print_string "\n") result;)

(* merged declaration, allow us to process declaration in multiple pass *)
(* first detect recursive decls then lexp decls*)
type mdecl =
  | Ldecl of symbol * pexp option * pexp option
  | Lmcall of symbol * sexp list

let lexp_detect_recursive pdecls =
  (* Pack mutually recursive declarations                 *)
  (* mutually recursive def must use forward declarations *)

  let decls = ref [] in
  let pending = ref [] in
  let merged = ref [] in

  List.iter (fun expr ->
    match expr with
      | Pexpr((l, s), pxp) ->(
        let was_forward = (List.exists
                      (fun (Ldecl((_, p), _, _)) -> p = s) !pending) in

        let is_empty = (List.length !pending) = 0 in
        let is_one = (List.length !pending) = 1 in

        (* This is a standard declaration: not forwarded *)
        if (was_forward = false) && is_empty then(
          decls := [Ldecl((l, s), Some pxp, None)]::!decls;
        )
        (* This is an annotated expression
         * or the last element of a mutually rec definition *)
        else if (was_forward && is_one) then (

          (* we know that names match already *)
          let ptp = (match (!pending) with
            | Ldecl(_, _, ptp)::[] -> ptp
            (* we already checked that len(pending) == 1*)
            | Ldecl(_, _, ptp)::_  -> typer_unreachable "Unreachable"
            | []                   -> typer_unreachable "Unreachable"
            | Lmcall _ :: _        -> typer_unreachable "Unreachable") in

          (* add declaration to merged decl *)
          merged := Ldecl((l, s), Some pxp, ptp)::(!merged);

          (* append decls *)
          decls := (List.rev !merged)::!decls;

          (* Reset State *)
          pending := [];
          merged := [];
        )
        (* This is a mutually recursive definition *)
        else (
          (* get pending element and remove it from the list *)
          let elem, lst = List.partition
                                (fun (Ldecl((_, n), _, _)) -> n = s) !pending in

          let _ = (match elem with
              (* nothing to merge *)
              | [] ->
                merged := Ldecl((l, s), Some pxp, None)::!merged;

              (* append new element to merged list *)
              | Ldecl((l, s), _, Some ptp)::[] ->
                merged := Ldecl((l, s), Some pxp, (Some ptp))::!merged;

              (* s should be unique *)
              | _ -> error l "declaration must be unique") in

          (* element is not pending anymore *)
          pending := lst;
        ))

      | Ptype((l, s), ptp) ->
        pending := Ldecl((l, s), None, Some ptp)::!pending

      (* macro will be handled later *)
      | Pmcall(a, sargs) ->
          decls := [Lmcall(a, sargs)]::!decls;

      ) pdecls;

      (List.rev !decls)

let main () =
    parse_args ();

    let arg_n = Array.length Sys.argv in

    let usage =
        "\n  Usage:   " ^ Sys.argv.(0) ^ " <file_name> [options]\n" in

    (*  Print Usage *)
    if arg_n == 1 then
        (Arg.usage (Arg.align arg_defs) usage)

    else if (!_format_mode) then (
        format_source ()
    )
    else(
        (if (!debug_arg) = 0 then make_default ());

        let filename = List.hd (!arg_files) in

        (* get pretokens*)
        print_string yellow;
        let pretoks = prelex_file filename in
        print_string reset;

        (if (get_p_option "pretok") then(
            print_string (make_title " PreTokens");
            debug_pretokens_print_all pretoks; print_string "\n"));

        (* get sexp/tokens *)
        print_string yellow;
        let toks = lex default_stt pretoks in
        print_string reset;

        (if (get_p_option "tok") then(
            print_string (make_title " Base Sexp");
            debug_sexp_print_all toks; print_string "\n"));

        (* get node sexp  *)
        print_string yellow;
        let nodes = sexp_parse_all_to_list default_grammar toks (Some ";") in
        print_string reset;

        (if (get_p_option "sexp") then(
            print_string (make_title " Node Sexp ");
            debug_sexp_print_all nodes; print_string "\n"));

        (* Parse All Declaration *)
        print_string yellow;
        let pexps = pexp_decls_all nodes in
        print_string reset;

        (if (get_p_option "pexp") then(
            print_string (make_title " Pexp ");
            debug_pexp_decls pexps; print_string "\n"));

        (* get lexp *)
        let octx = default_ectx in

        (* Debug declarations merging *)
        (if (get_p_option "merge-debug") then(
          let merged = lexp_detect_recursive pexps in

          List.iter (fun lst ->
            print_string (make_line '-' 80);
            print_string "\n";

              List.iter (fun v ->
                match v with
                  | Ldecl((l, s), pxp, ptp) -> (
                    lalign_print_string s 20;

                    let _ = match ptp with
                      | Some pxp -> pexp_print pxp;
                      | None -> print_string " " in

                    print_string "\n";
                    lalign_print_string s 20;

                    let _ = match pxp with
                      | Some pxp -> pexp_print pxp;
                      | None -> print_string " " in

                    print_string "\n")
                  | Lmcall((l, s), _ ) ->
                    print_string s; print_string "\n"
              ) lst;

            ) merged));

        (* debug lexp parsing once merged *)
        print_string yellow;
        let lexps, nctx = try lexp_p_decls pexps octx
          with e ->
            print_string reset;
            raise e in
        print_string reset;

        (* use the new way of parsing expr *)
        let ctx = nctx in
        let flexps = List.flatten lexps in

        (if (get_p_option "lexp-merge-debug") then(
          List.iter (fun ((l, s), lxp, ltp) ->
            lalign_print_string s 20;
            lexp_print ltp; print_string "\n";

            lalign_print_string s 20;
            lexp_print lxp; print_string "\n";

            ) flexps));

        (* get typecheck context *)
        let lctx_to_cctx (lctx: elab_context) =
          let (_, env) = ctx in env in

        (if (get_p_option "typecheck") then(
            print_string (make_title " TYPECHECK ");

            let cctx = lctx_to_cctx ctx in
            (* run type check *)
            List.iter (fun (_, lxp, _)
                       -> let _ = OL.check VMap.empty cctx lxp in ())
                      flexps;

            print_string ("    " ^ (make_line '-' 76));
            print_string "\n";));

        (if (get_p_option "lexp") then(
            print_string (make_title " Lexp ");
            debug_lexp_decls flexps; print_string "\n"));

        (if (get_p_option "lctx") then(
           print_lexp_ctx (ectx_to_lctx nctx); print_string "\n"));

        (* Type erasure *)
        let clean_lxp = List.map OL.clean_decls lexps in

        (* Eval declaration *)
        let rctx = default_rctx in
        print_string yellow;
        let rctx = (try eval_decls_toplevel clean_lxp rctx;
            with e ->
                print_string reset;
                print_rte_ctx (!_global_eval_ctx);
                print_eval_trace None;
                raise e) in
        print_string reset;

        (if (get_p_option "rctx") then(
            print_rte_ctx rctx; print_string "\n"));

        (* Eval Each Expression *)
        print_string (make_title " Eval Print ");

        (try
            (* Check if main is present *)
            let main = (senv_lookup "main" nctx) in

            (* get main body *)
            let body = (get_rte_variable (Some "main") main rctx) in

            (* eval main *)
                print_eval_result 1 body

        with
            Not_found -> ()
        )
    )

let _ = main ()
