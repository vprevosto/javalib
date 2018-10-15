(*
 * This file is part of Javalib
 * Copyright (c)2004 Nicolas Cannasse
 * Copyright (c)2007 Tiphaine Turpin (Université de Rennes 1)
 * Copyright (c)2007, 2008 Laurent Hubert (CNRS)
 * Copyright (c)2009, Frederic Dabrowski (INRIA)
 *
 * This software is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * version 2.1, with the special exception on linking described in file
 * LICENSE.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this program.  If not, see
 * <http://www.gnu.org/licenses/>.
 *)

open JClassLow
open JLib.IO.BigEndian
open JBasics
open JBasicsLow
open JParseSignature

type tmp_constant =
  | ConstantClass of int
  | ConstantField of int * int
  | ConstantMethod of int * int
  | ConstantInterfaceMethod of int * int
  | ConstantMethodType of int
  | ConstantMethodHandle of int * int
  | ConstantInvokeDynamic of int * int
  | ConstantString of int
  | ConstantInt of int32
  | ConstantFloat of float
  | ConstantLong of int64
  | ConstantDouble of float
  | ConstantNameAndType of int * int
  | ConstantStringUTF8 of string
  | ConstantUnusable

let parse_constant max ch =
  let cid = JLib.IO.read_byte ch in
  let index() =
    let n = read_ui16 ch in
    if n = 0 || n >= max
      then raise (Class_structure_error ("1: Illegal indexz in constant pool: " ^ string_of_int n));
      n
  in
    match cid with
      | 7 ->
	  ConstantClass (index())
      | 9 ->
	  let n1 = index() in
	  let n2 = index() in
	    ConstantField (n1,n2)
      | 10 ->
	  let n1 = index() in
	  let n2 = index() in
	    ConstantMethod (n1,n2)
      | 11 ->
	  let n1 = index() in
	  let n2 = index() in
            ConstantInterfaceMethod (n1,n2)
      | 15 ->
          let kind = JLib.IO.read_byte ch in
          let n2 = index() in
            ConstantMethodHandle (kind,n2)
      | 16 ->
          let n1 = index() in
            ConstantMethodType n1
      | 18 ->
          let n1 = read_ui16 ch in
          let n2 = index() in
            ConstantInvokeDynamic (n1,n2)
      | 8 ->
	  ConstantString (index())
      | 3 ->
	  ConstantInt (read_real_i32 ch)
      | 4 ->
	  let f = Int32.float_of_bits (read_real_i32 ch) in
	    ConstantFloat f
      | 5 ->
	  ConstantLong (read_i64 ch)
      | 6 ->
	  ConstantDouble (read_double ch)
      | 12 ->
	  let n1 = index() in
	  let n2 = index() in
	    ConstantNameAndType (n1,n2)
      | 1 ->
	  let len = read_ui16 ch in
	  let str = JLib.IO.really_nread_string ch len in
	    ConstantStringUTF8 str
      | cid ->
	  raise (Class_structure_error ("Illegaly constant kind: " ^ string_of_int cid))

let class_flags =
  [|`AccPublic; `AccRFU 0x2; `AccRFU 0x4; `AccRFU 0x8;
    `AccFinal; `AccSuper; `AccRFU 0x40; `AccRFU 0x80;
    `AccRFU 0x100; `AccInterface; `AccAbstract; `AccRFU 0x800;
    `AccSynthetic; `AccAnnotation; `AccEnum; `AccRFU 0x8000|]
let innerclass_flags =
  [|`AccPublic; `AccPrivate; `AccProtected; `AccStatic;
    `AccFinal; `AccRFU 0x20; `AccRFU 0x40; `AccRFU 0x80;
    `AccRFU 0x100; `AccInterface; `AccAbstract; `AccRFU 0x800;
    `AccSynthetic; `AccAnnotation; `AccEnum; `AccRFU 0x8000|]
let field_flags =
  [|`AccPublic; `AccPrivate; `AccProtected; `AccStatic;
    `AccFinal; `AccRFU 0x20; `AccVolatile; `AccTransient;
    `AccRFU 0x100; `AccRFU 0x200; `AccRFU 0x400; `AccRFU 0x800;
    `AccSynthetic; `AccRFU 0x2000; `AccEnum; `AccRFU 0x8000|]
let method_flags =
  [|`AccPublic; `AccPrivate; `AccProtected; `AccStatic;
    `AccFinal; `AccSynchronized; `AccBridge; `AccVarArgs;
    `AccNative; `AccRFU 0x200; `AccAbstract; `AccStrict;
    `AccSynthetic; `AccRFU 0x2000; `AccRFU 0x4000; `AccRFU 0x8000|]

let parse_access_flags all_flags ch =
  let fl = read_ui16 ch in
  let flags = ref [] in
    Array.iteri
      (fun i f -> if fl land (1 lsl i) <> 0 then flags := f :: !flags)
      all_flags;
    !flags

let parse_stackmap_type_info consts ch = match JLib.IO.read_byte ch with
  | 0 -> VTop
  | 1 -> VInteger
  | 2 -> VFloat
  | 3 -> VDouble
  | 4 -> VLong
  | 5 -> VNull
  | 6 -> VUninitializedThis
  | 7 -> VObject (get_object_type consts (read_ui16 ch))
  | 8 -> VUninitialized (read_ui16 ch)
  | n -> raise (Class_structure_error ("Illegal stackmap type: " ^ string_of_int n))

let parse_stackmap_frame consts ch =
  let parse_type_info_array ch nb_item =
    JLib.List.init nb_item (fun _ -> parse_stackmap_type_info consts ch)
  in let offset = read_ui16 ch in
  let number_of_locals = read_ui16 ch in
  let locals = parse_type_info_array ch number_of_locals in
  let number_of_stack_items = read_ui16 ch in
  let stack = parse_type_info_array ch number_of_stack_items in
    (offset,locals,stack)


(***************************************************************************)
(* DFr : Addition for 1.6 stackmap *****************************************)
(***************************************************************************)
let parse_stackmap_table consts ch =
  let kind = JLib.IO.read_byte ch
  in
  let stackmap =
    if ((kind>=0) && (kind<=63)) then SameFrame(kind)
    else if ((kind >=64) && (kind <=127)) then
      let vtype = parse_stackmap_type_info consts ch in
	SameLocals(kind,vtype)
    else if (kind=247) then
      let offset_delta = read_ui16 ch
      and vtype = parse_stackmap_type_info consts ch in
	SameLocalsExtended(kind,offset_delta,vtype)
    else if ((kind >=248) && (kind <=250)) then
      let offset_delta = read_ui16 ch in ChopFrame(kind,offset_delta)
    else if (kind=251) then
      let offset_delta = read_ui16 ch in SameFrameExtended(kind,offset_delta)
    else if ((kind >=252) && (kind <=254)) then
      let offset_delta = read_ui16 ch in
      let locals = JLib.List.init (kind-251)
	(fun _ -> parse_stackmap_type_info consts ch) in
	AppendFrame(kind,offset_delta,locals)
    else if (kind=255) then
      let offset_delta = read_ui16 ch in
      let nlocals = read_ui16 ch in
      let locals = JLib.List.init nlocals
	(fun _ -> parse_stackmap_type_info consts ch) in
      let nstack = read_ui16 ch in
      let stack = JLib.List.init nstack
	(fun _ -> parse_stackmap_type_info consts ch) in
	FullFrame(kind,offset_delta,locals,stack)
    else (print_string("Invalid stackmap kind\n");SameLocals(-1,VTop))
  in stackmap


(* Annotation parsing *)
let rec parse_element_value consts ch =
  let tag = JLib.IO.read_byte ch in
    match Char.chr tag with
      | ('B' | 'C' | 'S' | 'Z' | 'I' | 'D' | 'F' | 'J' ) as c -> (* constants *)
          let constant_value_index = read_ui16 ch in
          let cst = get_constant_value consts constant_value_index
          in
            begin
              match c,cst with
                | 'B', ConstInt i -> EVCstByte (Int32.to_int i)
                | 'C', ConstInt i -> EVCstChar (Int32.to_int i)
                | 'S', ConstInt i -> EVCstShort (Int32.to_int i)
                | 'Z', ConstInt i -> EVCstBoolean (Int32.to_int i)
                | 'I', ConstInt i -> EVCstInt i
                | 'D', ConstDouble d -> EVCstDouble d
                | 'F', ConstFloat f -> EVCstFloat f
                | 'J', ConstLong l -> EVCstLong l
                | ('B' | 'C' | 'S' | 'Z' | 'I' | 'D' | 'F' | 'J' ),_ ->
                    raise
                      (Class_structure_error
                         "A such constant cannot be referenced in such  an \
                          annotation element")
                | _,_ -> assert false
            end
      | 's'                             (* string *)
        ->
          let constant_value_index = read_ui16 ch in
          let cst = get_string consts constant_value_index
          in
            EVCstString cst
      | 'e' ->                          (* enum constant *)
          let type_name_index = read_ui16 ch
          and const_name_index = read_ui16 ch in
          let enum_type =
            let vt =
              parse_field_descriptor (get_string consts type_name_index)
            in match vt with
              | TObject (TClass c) -> c
              | _ -> assert false
          and const_name = get_string consts const_name_index
          in
            EVEnum (enum_type,const_name)
              (* failwith ("not implemented EVEnum("^type_name^","^const_name^")") *)
      | 'c' ->                          (* class constant *)
          let descriptor = get_string consts (read_ui16 ch)
          in
            if descriptor = "V"
            then EVClass None
            else EVClass (Some (parse_field_descriptor descriptor))
      | '@' ->                          (* annotation type *)
          EVAnnotation (parse_annotation consts ch)
      | '[' ->                          (* array *)
          let num_values = read_ui16 ch in
          let values =
            JLib.List.init num_values (fun _ -> parse_element_value consts ch)
          in EVArray values
      | _ ->
          raise (Class_structure_error
                   "invalid tag in a element_value of an annotation")

and parse_annotation consts ch =
  let type_index = read_ui16 ch
  and nb_ev_pairs = read_ui16 ch
  in
  let kind =
    let kind_value_type =
      parse_field_descriptor (get_string consts type_index)
    in
      match kind_value_type with
        | TObject (TClass cn) -> cn
        | _ ->
            raise
              (Class_structure_error
                 "An annotation should only be a class")
  and ev_pairs =
    JLib.List.init
      nb_ev_pairs
      (fun _ ->
         let name = get_string consts (read_ui16 ch)
         and value = parse_element_value consts ch
         in (name, value))
  in
    {kind = kind;
     element_value_pairs = ev_pairs}


let parse_annotations consts ch =
  let num_annotations = read_ui16 ch
  in
    JLib.List.init num_annotations (fun _ -> parse_annotation consts ch)

let parse_parameter_annotations consts ch =
  let num_parameters = JLib.IO.read_byte ch
  in
    JLib.List.init num_parameters (fun _ -> parse_annotations consts ch)


let rec parse_code consts ch =
  let max_stack = read_ui16 ch in
  let max_locals = read_ui16 ch in
  let clen =
    match read_i32 ch with
      | toobig when toobig > 65535 ->
	  raise (Class_structure_error
		   "There must be less than 65536 bytes of instructions in a Code attribute")
      | ok -> ok
  in
  let code =
    JParseCode.parse_code ch clen
  in
  let exc_tbl_length = read_ui16 ch in
  let exc_tbl =
    JLib.List.init
      exc_tbl_length
      (fun _ ->
	 let spc = read_ui16 ch in
	 let epc = read_ui16 ch in
	 let hpc = read_ui16 ch in
	 let ct =
	   match read_ui16 ch with
	     | 0 -> None
	     | ct ->
		 match get_constant consts ct with
		   | ConstValue (ConstClass (TClass c)) -> Some c
		   | _ -> raise (Class_structure_error ("Illegal class index (does not refer to a constant class)"))
	 in
	   {
	     JCode.e_start = spc;
	     JCode.e_end = epc;
	     JCode.e_handler = hpc;
	     JCode.e_catch_type = ct;
	   }
      ) in
  let attrib_count = read_ui16 ch in
  let attribs =
    JLib.List.init
      attrib_count
      (fun _ ->
	 parse_attribute
	   [`LineNumberTable ; `LocalVariableTable ; `StackMap]
	   consts ch) in
    {
      c_max_stack = max_stack;
      c_max_locals = max_locals;
      c_exc_tbl = exc_tbl;
      c_attributes = attribs;
      c_code = code;
    }

(* Parse an attribute, if its name is in list. *)
and parse_attribute list consts ch =
  let aname = get_string_ui16 consts ch in
  let error() = raise (Class_structure_error ("Ill-formed attribute " ^ aname)) in
  let alen = read_i32 ch in
  let check name =
    if not (List.mem name list)
    then raise Exit
  in
    try
      match aname with
	| "Signature" ->
	    check `Signature;
	    if alen <> 2 then error();
	    AttributeSignature (get_string_ui16 consts ch)
	| "EnclosingMethod" ->
	    check `EnclosingMethod;
	    if alen <> 4 then error();
	    let c = get_class_ui16 consts ch
	    and m = match read_ui16 ch with
	      | 0 -> None
	      | n ->
		  match get_constant consts n with
		    | ConstNameAndType (n,t) -> Some (n,t)
		    | _ -> raise (Class_structure_error "EnclosingMethod attribute cannot refer to a constant which is not a NameAndType")
	    in
	      AttributeEnclosingMethod (c,m)
	| "SourceDebugExtension" ->
	    check `SourceDebugExtension;
	    AttributeSourceDebugExtension (JLib.IO.really_nread_string ch alen)
	| "SourceFile" -> check `SourceFile;
	    if alen <> 2 then error();
	    AttributeSourceFile (get_string_ui16 consts ch)
	| "ConstantValue" -> check `ConstantValue;
	    if alen <> 2 then error();
	    AttributeConstant (get_constant_value consts (read_ui16 ch))
	| "Code" -> check `Code;
	    let ch = JLib.IO.input_string (JLib.IO.really_nread_string ch alen) in
	    let parse_code _ =
	      let ch, count = JLib.IO.pos_in ch in
	      let code = parse_code consts ch
	      in
		if count() <> alen then error();
		code
	    in
	      AttributeCode (Lazy.from_fun parse_code)
	| "Exceptions" -> check `Exceptions;
	    let nentry = read_ui16 ch in
	      if nentry * 2 + 2 <> alen then error();
	      AttributeExceptions
		(JLib.List.init
		   nentry
		   (function _ ->
		      get_class_ui16 consts ch))
	| "InnerClasses" -> check `InnerClasses;
	    let nentry = read_ui16 ch in
	      if nentry * 8 + 2 <> alen then error();
	      AttributeInnerClasses
		(JLib.List.init
		   nentry
		   (function _ ->
		      let inner =
			match (read_ui16 ch) with
			  | 0 -> None
			  | i -> Some (get_class consts i) in
		      let outer =
			match (read_ui16 ch) with
			  | 0 -> None
			  | i -> Some (get_class consts i) in
		      let inner_name =
			match (read_ui16 ch) with
			  | 0 -> None
			  | i -> Some (get_string consts i) in
		      let flags = parse_access_flags innerclass_flags ch in
			inner, outer, inner_name, flags))
	| "Synthetic" -> check `Synthetic;
	    if alen <> 0 then error ();
	    AttributeSynthetic
	| "LineNumberTable" -> check `LineNumberTable;
	    let nentry = read_ui16 ch in
	      if nentry * 4 + 2 <> alen then error();
	      AttributeLineNumberTable
		(JLib.List.init
		   nentry
		   (fun _ ->
		      let pc = read_ui16 ch in
		      let line = read_ui16 ch in
			pc , line))
	| "LocalVariableTable" -> check `LocalVariableTable;
	    let nentry = read_ui16 ch in
	      if nentry * 10 + 2 <> alen then error();
	      AttributeLocalVariableTable
		(JLib.List.init
		   nentry
		   (function _ ->
		      let start_pc = read_ui16 ch in
		      let length = read_ui16 ch in
		      let name = get_string_ui16 consts ch in
		      let signature =
                        parse_field_descriptor
			  (get_string_ui16 consts ch) in
		      let index = read_ui16 ch in
			start_pc, length, name, signature, index))
        | "LocalVariableTypeTable" -> check `LocalVariableTypeTable;
            let nentry = read_ui16 ch in
              if nentry *10 + 2 <> alen then error();
              AttributeLocalVariableTypeTable
                (JLib.List.init
                nentry
                (fun _ ->
                   let start_pc = read_ui16 ch in
                   let length = read_ui16 ch in
                   let name = get_string_ui16 consts ch in
                   let signature =
                     parse_FieldTypeSignature
                       (get_string_ui16 consts ch) in
                   let index = read_ui16 ch in
                     start_pc, length, name, signature, index))
	| "Deprecated" -> check `Deprecated;
	    if alen <> 0 then error ();
	    AttributeDeprecated
	| "StackMap" -> check `StackMap;
	    let ch, count = JLib.IO.pos_in ch in
	    let nb_stackmap_frames = read_ui16 ch in
	    let stackmap =
	      JLib.List.init nb_stackmap_frames
		(fun _ -> parse_stackmap_frame consts ch )
	    in
	      if count() <> alen then error();
	      AttributeStackMap stackmap
	| "StackMapTable" ->
	    (* DFr : Addition for 1.6 stackmap *)
	    check `StackMap;
	    let ch, count = JLib.IO.pos_in ch in
	    let nentry = read_ui16 ch in
	    let stackmap =
	      JLib.List.init nentry (fun _ -> parse_stackmap_table consts ch )
	    in
	      if count() <> alen then error();
	      AttributeStackMapTable stackmap
        | "RuntimeVisibleAnnotations" ->
            check `RuntimeVisibleAnnotations;
            AttributeRuntimeVisibleAnnotations (parse_annotations consts ch)
        | "RuntimeInvisibleAnnotations" ->
            check `RuntimeInvisibleAnnotations;
            AttributeRuntimeInvisibleAnnotations (parse_annotations consts ch)
        | "RuntimeVisibleParameterAnnotations" ->
            check `RuntimeVisibleParameterAnnotations;
            AttributeRuntimeVisibleParameterAnnotations
              (parse_parameter_annotations consts ch)
        | "RuntimeInvisibleParameterAnnotations" ->
            check `RuntimeInvisibleParameterAnnotations;
            AttributeRuntimeInvisibleParameterAnnotations
              (parse_parameter_annotations consts ch)
        | "AnnotationDefault" ->
            check `AnnotationDefault;
            AttributeAnnotationDefault (parse_element_value consts ch)
        | "BootstrapMethods" ->
            (* added in 1.8 to support invokedynamic *)
            check `BootstrapMethods;
            let nentry = read_ui16 ch in
            AttributeBootstrapMethods
              (JLib.List.init
	         nentry
		   (function _ ->
		      let bootstrap_method_ref = read_ui16 ch in
		      let num_bootstrap_arguments = read_ui16 ch in
                      let bootstrap_arguments =
                        JLib.List.init num_bootstrap_arguments (function _ -> read_ui16 ch) in
                      { bootstrap_method_ref; num_bootstrap_arguments; bootstrap_arguments; }))
	| _ -> raise Exit
    with
	Exit -> AttributeUnknown (aname,JLib.IO.really_nread_string ch alen)

let parse_field consts ch =
  let acc = parse_access_flags field_flags ch in
  let name = get_string_ui16 consts ch in
  let sign = parse_field_descriptor (get_string_ui16 consts ch) in
  let attrib_count = read_ui16 ch in
  let attrib_to_parse =
    let base_attrib =
      [`Synthetic ; `Deprecated ; `Signature;
       `RuntimeVisibleAnnotations; `RuntimeInvisibleAnnotations;
       `RuntimeVisibleParameterAnnotations;
       `RuntimeInvisibleParameterAnnotations;]
    in
      if List.exists ((=)`AccStatic) acc
      then  `ConstantValue:: base_attrib
      else  base_attrib
  in
  let attribs =
    JLib.List.init
      attrib_count
      (fun _ -> parse_attribute attrib_to_parse consts ch) in
    {
      f_name = name;
      f_descriptor = sign;
      f_attributes = attribs;
      f_flags = acc;
    }

let parse_method consts ch =
  let acc = parse_access_flags method_flags ch in
  let name = get_string_ui16 consts ch in
  let sign = parse_method_descriptor (get_string_ui16 consts ch) in
  let attrib_count = read_ui16 ch in
  let attribs = JLib.List.init attrib_count
    (fun _ ->
       let to_parse =
         [`Code ; `Exceptions ; `Synthetic ;
	  `Deprecated ; `Signature;
          `AnnotationDefault;
          `RuntimeVisibleAnnotations; `RuntimeInvisibleAnnotations;
          `RuntimeVisibleParameterAnnotations;
          `RuntimeInvisibleParameterAnnotations;]
       in
         parse_attribute to_parse consts ch)
  in
    {
      m_name = name;
      m_descriptor = sign;
      m_attributes = attribs;
      m_flags = acc;
    }

let rec expand_constant consts n =
  let expand name cl nt =
    match expand_constant consts cl with
      | ConstValue (ConstClass c) ->
	  (match expand_constant consts nt with
	     | ConstNameAndType (n,s) -> (c,n,s)
	     | _ -> raise (Class_structure_error ("Illegal constant refered in place of NameAndType in " ^ name ^ " constant")))
      | _ -> raise (Class_structure_error ("Illegal constant refered in place of a ConstValue in " ^ name ^ " constant"))
  in
    match consts.(n) with
      | ConstantClass i ->
	  (match expand_constant consts i with
	     | ConstStringUTF8 s -> ConstValue (ConstClass (parse_objectType s))
	     | _ -> raise (Class_structure_error ("Illegal constant refered in place of a Class constant")))
      | ConstantField (cl,nt) ->
	  (match expand "Field" cl nt with
	     | TClass c, n, SValue v -> ConstRef (ConstField (c, make_fs n v))
	     | TClass _, _, _ -> raise (Class_structure_error ("Illegal type in Field constant: " ^ ""))
	     | _ -> raise (Class_structure_error ("Illegal constant refered in place of a Field constant")))
      | ConstantMethod (cl,nt) ->
	  (match expand "Method" cl nt with
	     | c, n, SMethod (args,rtype) -> ConstRef (ConstMethod (c, make_ms n args rtype))
	     | _, _, SValue _ -> raise (Class_structure_error ("Illegal type in Method constant")))
      | ConstantInterfaceMethod (cl,nt) ->
	  (match expand "InterfaceMethod" cl nt with
	     | TClass c, n, SMethod (args,rtype) ->
                 ConstRef(ConstInterfaceMethod (c, make_ms n args rtype))
	     | TClass _, _, _ -> raise (Class_structure_error ("Illegal type in Interface Method constant"))
      | _, _, _ -> raise (Class_structure_error ("Illegal constant refered in place of an Interface Method constant")))
      | ConstantMethodType i ->
          (match expand_constant consts i with
           | ConstStringUTF8 s ->
               ConstMethodType (parse_method_descriptor s)
            | _ -> raise (Class_structure_error ("Illegal constant referred in place of a MethodType constant")))
      | ConstantMethodHandle (kind, index) ->
          (match kind, expand_constant consts index with
           | 1, ConstRef (ConstField _ as const) ->
              ConstMethodHandle (`GetField, const)
           | 2, ConstRef (ConstField _ as const) ->
              ConstMethodHandle (`GetStatic, const)
           | 3, ConstRef (ConstField _ as const) ->
              ConstMethodHandle (`PutField, const)
           | 4, ConstRef (ConstField _ as const) ->
              ConstMethodHandle (`PutStatic, const)
           | 5, ConstRef (ConstMethod _ as const) ->
              ConstMethodHandle (`InvokeVirtual, const)
           | 6, ConstRef (ConstMethod _ | ConstInterfaceMethod _ as const) ->
              ConstMethodHandle (`InvokeStatic, const)
           | 7, ConstRef (ConstMethod _ | ConstInterfaceMethod _ as const) ->
              ConstMethodHandle (`InvokeSpecial, const)
           | 8, ConstRef (ConstMethod _ as const) ->
              ConstMethodHandle (`NewInvokeSpecial, const)
           | 9, ConstRef (ConstInterfaceMethod _ as const) ->
              ConstMethodHandle (`InvokeInterface, const)
           | n, c ->
               let s =
                 JLib.IO.output_string () in
               JDumpBasics.dump_constant s c;
               let str = JLib.IO.close_out s in
               raise (Class_structure_error ("Bad method handle constant " ^ (string_of_int n) ^ str)))
      | ConstantInvokeDynamic (bmi,nt) ->
          (match expand_constant consts nt with
           | ConstNameAndType (n, SMethod (args,rtype)) ->
               ConstInvokeDynamic (bmi, make_ms n args rtype)
           | _ -> raise (Class_structure_error ("Illegal constant referred in place of an InvokeDynamic constant")))
      | ConstantString i ->
	  (match expand_constant consts i with
	     | ConstStringUTF8 s -> ConstValue (ConstString (make_jstr s))
	     | _ -> raise (Class_structure_error ("Illegal constant refered in place of a String constant")))
      | ConstantInt i -> ConstValue (ConstInt i)
      | ConstantFloat f -> ConstValue (ConstFloat f)
      | ConstantLong l -> ConstValue (ConstLong l)
      | ConstantDouble f -> ConstValue (ConstDouble f)
      | ConstantNameAndType (n,t) ->
	  (match expand_constant consts n , expand_constant consts t with
	     | ConstStringUTF8 n , ConstStringUTF8 t -> ConstNameAndType (n,parse_descriptor t)
	     | ConstStringUTF8 _ , _ ->
		 raise (Class_structure_error ("Illegal type in a NameAndType constant"))
	     | _ -> raise (Class_structure_error ("Illegal constant refered in place of a NameAndType constant")))
      | ConstantStringUTF8 s -> ConstStringUTF8 s
      | ConstantUnusable -> ConstUnusable

let parse_class_low_level ch =
  let magic = read_real_i32 ch in
    if magic <> 0xCAFEBABEl then raise (Class_structure_error "Invalid magic number");
    let version_minor = read_ui16 ch in
    let version_major = read_ui16 ch in
    let constant_count = read_ui16 ch in
    let const_big = ref true in
    let consts =
      Array.init
	constant_count
	(fun _ ->
	   if !const_big then begin
	     const_big := false;
	     ConstantUnusable
	   end else
	     let c = parse_constant constant_count ch in
	       (match c with ConstantLong _ | ConstantDouble _ -> const_big := true | _ -> ());
	       c
	) in
    let consts = Array.mapi (fun i _ -> expand_constant consts i) consts in
    let flags = parse_access_flags class_flags ch in
    let this = get_class_ui16 consts ch in
    let super_idx = read_ui16 ch in
    let super = if super_idx = 0 then None else Some (get_class consts super_idx) in
    let interface_count = read_ui16 ch in
    let interfaces = JLib.List.init interface_count (fun _ -> get_class_ui16 consts ch) in
    let field_count = read_ui16 ch in
    let fields = JLib.List.init field_count (fun _ -> parse_field consts ch) in
    let method_count = read_ui16 ch in
    let methods = JLib.List.init method_count (fun _ -> parse_method consts ch) in
    let attrib_count = read_ui16 ch in
    let attribs =
      JLib.List.init
	attrib_count
	(fun _ ->
           let to_parse =
             [`Signature; `SourceFile; `Deprecated; `BootstrapMethods;
              `InnerClasses ;`EnclosingMethod; `SourceDebugExtension;
              `RuntimeVisibleAnnotations; `RuntimeInvisibleAnnotations;
              `RuntimeVisibleParameterAnnotations;
              `RuntimeInvisibleParameterAnnotations;]
           in
             parse_attribute
               to_parse
	       consts ch)
    in
      {j_consts = consts;
       j_flags = flags;
       j_name = this;
       j_super = super;
       j_interfaces = interfaces;
       j_fields = fields;
       j_methods = methods;
       j_attributes = attribs;
       j_version = {major=version_major; minor=version_minor};
      }

(* if the parsing raises a class_structure_error exception, we close the input ourself *)
let parse_class_low_level ch =
  try parse_class_low_level ch
  with Class_structure_error _ as e ->
    JLib.IO.close_in ch;
    raise e

let parse_class ch = JLow2High.low2high_class (parse_class_low_level ch)
