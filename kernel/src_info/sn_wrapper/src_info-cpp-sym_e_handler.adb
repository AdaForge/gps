separate (Src_Info.CPP)

--------------------
-- Sym_E_Handler --
--------------------

procedure Sym_E_Handler (Sym : FIL_Table)
is
   Decl_Info : E_Declaration_Info_List;
   E_Id      : String := Sym.Buffer
     (Sym.Identifier.First .. Sym.Identifier.Last);
begin

   Info ("Sym_E_Hanlder: '" & E_Id & "'");

   Insert_Declaration
     (Handler           => LI_Handler (Global_CPP_Handler),
      File              => Global_LI_File,
      List              => Global_LI_File_List,
      Symbol_Name       => E_Id,
      Source_Filename   =>
        Sym.Buffer (Sym.File_Name.First .. Sym.File_Name.Last),
      Location          => Sym.Start_Position,
      Kind              => Enumeration_Type,
      Scope             => Global_Scope,
      Declaration_Info  => Decl_Info);

end Sym_E_Handler;
