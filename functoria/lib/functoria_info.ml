(*
 * Copyright (c) 2015 Gabriel Radanne <drupyog@zoho.com>
 * Copyright (c) 2015-2020 Thomas Gazagnaire <thomas@gazagnaire.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

open Astring

module Package = Functoria_package
module Key = Functoria_key

type t = {
  name: string;
  output: string option;
  build_dir: Fpath.t;
  keys: Key.Set.t;
  context: Key.context;
  packages: Package.t String.Map.t;
}

let name t = t.name
let build_dir t = t.build_dir
let output t = t.output
let with_output t output = { t with output = Some output }

let libraries ps =
  let libs p =
    if Package.build_dependency p
    then String.Set.empty
    else String.Set.of_list (Package.libraries p)
  in
  String.Set.elements
    (List.fold_left String.Set.union String.Set.empty
       (List.map libs ps))

let packages t = List.map snd (String.Map.bindings t.packages)
let libraries t = libraries (packages t)
let package_names t = List.map Package.name (packages t)
let pins t =
  List.fold_left
    (fun acc p -> match Package.pin p with
       | None -> acc
       | Some u -> (Package.name p, u) :: acc)
    [] (packages t)

let keys t = Key.Set.elements t.keys
let context t = t.context

let create ~packages ~keys ~context ~name ~build_dir =
  let keys = Key.Set.of_list keys in
  let packages = List.fold_left (fun m p ->
      let n = Package.name p in
      match String.Map.find n m with
      | None -> String.Map.add n p m
      | Some p' -> match Package.merge p p' with
        | Some p -> String.Map.add n p m
        | None -> m
    ) String.Map.empty packages
  in
  { name; build_dir; keys; packages; context; output = None }

let pp_packages ?(surround = "") ?sep ppf t =
  Fmt.pf ppf "%a" (Fmt.iter ?sep List.iter (Package.pp ~surround)) (packages t)

let pp verbose ppf ({ name ; build_dir ; keys ; context ; output; _ } as t) =
  let show name = Fmt.pf ppf "@[<2>%s@ %a@]@," name in
  let list = Fmt.iter ~sep:(Fmt.unit ",@ ") List.iter Fmt.string in
  show "Name      " Fmt.string name;
  show "Build-dir " Fpath.pp build_dir;
  show "Keys      " (Key.pps context) keys;
  show "Output    " Fmt.(option string) output;
  if verbose then show "Libraries " list (libraries t);
  if verbose then
    show "Packages  "
      (pp_packages ?surround:None ~sep:(Fmt.unit ",@ ")) t

let pp_opam ?name ppf t =
  let name = match name with None -> t.name | Some x -> x in
  Fmt.pf ppf "opam-version: \"2.0\"@." ;
  Fmt.pf ppf "name: \"%s\"@." name ;
  Fmt.pf ppf "depends: [ @[<hv>%a@]@ ]@."
    (pp_packages ~surround:"\"" ~sep:(Fmt.unit "@ ")) t ;
  match pins t with
  | [] -> ()
  | pin_depends ->
    let pp_pin ppf (package, url) =
      Fmt.pf ppf "[\"%s.dev\" %S]" package url
    in
    Fmt.pf ppf "pin-depends: [ @[<hv>%a@]@ ]@."
      Fmt.(list ~sep:(unit "@ ") pp_pin) pin_depends
