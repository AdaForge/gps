with GNAT.IO;                   use GNAT.IO;
with Csets;                     use Csets;
with Prj;                       use Prj;
with Prj.Env;                   use Prj.Env;
with Prj.Part;                  use Prj.Part;
with Prj.Proc;                  use Prj.Proc;
with Prj.Tree;                  use Prj.Tree;
with Prj.Util;                  use Prj.Util;
with Errout;                    use Errout;
with Namet;                     use Namet;
with Snames;                    use Snames;
with Types;                     use Types;
with GNAT.OS_Lib;               use GNAT.OS_Lib;
with GNAT.Directory_Operations; use GNAT.Directory_Operations;
with Ada.Command_Line;          use Ada.Command_Line;

package body Convert.Gpr is

   procedure Output_Path (Path : String_Access; Prefix : String);
   --  Output one line for each directory in path. Each line starts with
   --  Prefix.

   function Output_Single_Attr
     (Project_View : Project_Id;
      Gpr_Name     : String;
      Default      : String := "";
      Pkg_Name     : String := "") return String;
   --  Get the value of Gpr_Name in Project_View, and return it.
   --  Default is used if the attribute was not found in Project_View
   --
   --  The attribute is search in the package Pkg_Name, if this is not the
   --  empty string.

   function Output_Array_Attr
     (Project_View : Project_Id;
      Gpr_Name     : String;
      Default      : String := "";
      Pkg_Name     : String := "";
      Index        : String := "") return String;
   --  Same as Output_Single_Attr, but for an array attribute

   -----------------
   -- Output_Path --
   -----------------

   procedure Output_Path (Path : String_Access; Prefix : String) is
      Start, Last : Natural;
   begin
      Start := Path'First;
      while Start <= Path'Last loop
         Last := Start;
         while Last <= Path'Last
           and then Path (Last) /= Path_Separator
         loop
            Last := Last + 1;
         end loop;

         Put_Line (Prefix
                   & Format_Pathname (Path (Start .. Last - 1), UNIX) & '/');
         Start := Last + 1;
      end loop;
   end Output_Path;

   ------------------------
   -- Output_Single_Attr --
   ------------------------

   function Output_Single_Attr
     (Project_View : Project_Id;
      Gpr_Name : String;
      Default : String := "";
      Pkg_Name : String := "") return String
   is
      Attr_Id : Name_Id;
      Value : Prj.Variable_Value;
      Str : String_List_Id;
      Pkg_Id : Package_Id := No_Package;
      Decl : Variable_Id;
   begin
      Name_Len := Gpr_Name'Length;
      Name_Buffer (1 .. Name_Len) := Gpr_Name;
      Attr_Id := Name_Find;

      if Pkg_Name /= "" then
         Name_Len := Pkg_Name'Length;
         Name_Buffer (1 .. Name_Len) := Pkg_Name;
         Pkg_Id := Value_Of
           (Name_Find,
            In_Packages => Projects.Table (Project_View).Decl.Packages);
      end if;

      if Pkg_Id = No_Package then
         Decl := Projects.Table (Project_View).Decl.Attributes;
      else
         Decl := Packages.Table (Pkg_Id).Decl.Attributes;
      end if;

      Value := Prj.Util.Value_Of
        (Variable_Name => Attr_Id,
         In_Variables  => Decl);

      if Value.Kind = Single then
         Get_Name_String (Value.Value);
         return Name_Buffer (1 .. Name_Len);

      elsif Value.Kind = List then
         Str := Value.Values;
         Get_Name_String (String_Elements.Table (Str).Value);
         return Name_Buffer (1 .. Name_Len);
      end if;

      return Default;

   exception
      when others =>
         return Default;
   end Output_Single_Attr;

   -----------------------
   -- Output_Array_Attr --
   -----------------------

   function Output_Array_Attr
     (Project_View : Project_Id;
      Gpr_Name : String;
      Default : String := "";
      Pkg_Name : String := "";
      Index  : String := "") return String
   is
      Attr_Id : Name_Id;
      Pkg_Id : Package_Id := No_Package;
      Decl : Array_Id;
      Elemt : Array_Element_Id;
      Idx : Name_Id;
   begin
      Name_Len := Gpr_Name'Length;
      Name_Buffer (1 .. Name_Len) := Gpr_Name;
      Attr_Id := Name_Find;

      if Pkg_Name /= "" then
         Name_Len := Pkg_Name'Length;
         Name_Buffer (1 .. Name_Len) := Pkg_Name;
         Pkg_Id := Value_Of
           (Name_Find,
            In_Packages => Projects.Table (Project_View).Decl.Packages);
      end if;

      if Pkg_Id = No_Package then
         Decl := Projects.Table (Project_View).Decl.Arrays;
      else
         Decl := Packages.Table (Pkg_Id).Decl.Arrays;
      end if;

      Elemt := Value_Of (Attr_Id, In_Arrays => Decl);

      Name_Len := Index'Length;
      Name_Buffer (1 .. Name_Len) := Index;
      Idx := Name_Find;

      Idx := Value_Of (Idx, In_Array => Elemt);
      if Idx = No_Name then
         return Default;
      else
         return Get_Name_String (Idx);
      end if;

   exception
      when others =>
         return Default;
   end Output_Array_Attr;

   -----------------------------
   -- Convert_From_Gpr_To_Adp --
   -----------------------------

   procedure Convert_From_Gpr_To_Adp (Gpr_Filename : String) is
      Project : Project_Node_Id;
      Project_View : Project_Id;
      Ide_Package : constant String := "ide";
      Success : Boolean;
   begin
      Namet.Initialize;
      Csets.Initialize;
      Snames.Initialize;
      Prj.Initialize;
      Prj.Tree.Initialize;

      Change_Dir (Dir_Name (Gpr_Filename));
      Parse (Project, Gpr_Filename, Always_Errout_Finalize => True);
      Process (Project_View, Success, Project, Report_Error => null);
      Errout.Finalize;

      if Success then
         declare
            Compiler : constant String := Output_Array_Attr
              (Project_View, "compiler_command", "gnatmake",
               Ide_Package, "ada");
            Debugger : constant String := Output_Single_Attr
              (Project_View, "debugger_command", "", Ide_Package);
            List : constant String := Output_Single_Attr
              (Project_View, "gnatlist", "", Ide_Package);
            Default_List : constant String := "gnatls";
         begin
            Output_Path (Ada_Include_Path (Project_View), "src_dir=");
            Output_Path (Ada_Objects_Path (Project_View), "obj_dir=");
            Put_Line
              ("build_dir=" &
               Get_Name_String (Projects.Table (Project_View).Exec_Directory));
            Put_Line ("comp_opt=-gnatQ -P" & Gpr_Filename);
            Put_Line ("make_cmd=" & Compiler & " ${comp_opt} ${main}");
            Put_Line ("comp_cmd=" & Compiler
                      & " -u -f ${comp_opt} ${full_current}");
            Put_Line ("run_cmd=cd ${build_dir}");
            Put_Line ("run_cmd=${main}");
            Put_Line ("check_cmd=cd ${build_dir}");
            Put_Line ("check_cmd=" & Compiler
                      & " -u -f -gnats ${comp_opt} ${full_current}");
            Put_Line ("debug_pre_cmd=cd ${build_dir}");
            Put_Line ("debug_post_cmd=");

            if Debugger /= "" then
               Put_Line ("debug_cmd=" & Debugger & " ${main}");
            end if;

            if List /= ""
              and then List'Length > Default_List'Length
              and then List (List'Last - Default_List'Length + 1 .. List'Last)
                = Default_List
            then
               Put_Line ("cross_prefix=" &
                         List (List'First .. List'Last - Default_List'Length));
            end if;

            Put_Line ("main_unit=");
            Put_Line ("remote_machine=" & Output_Single_Attr
                      (Project_View, "remote_host", "", Ide_Package));
            Put_Line ("main=" & Output_Single_Attr
                      (Project_View, "main", "${full_current}", ""));
         end;
      else
         Set_Exit_Status (Failure);
      end if;
   end Convert_From_Gpr_To_Adp;

end Convert.Gpr;
