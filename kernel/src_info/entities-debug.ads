with GNAT.IO;

package Entities.Debug is

   type Output_Proc is access procedure (Str : String);
   Output_Line : Output_Proc := GNAT.IO.Put_Line'Access;
   Output      : Output_Proc := GNAT.IO.Put'Access;
   --  The procedure used for output.

   procedure Set_Default_Output;
   --  Restore the default output procs

   procedure Dump (Db : Entities_Database);
   --  Dump the contents of the Db database to standard_output

   procedure Dump (Entity : Entity_Information; Full : Boolean; Name : String);
   procedure Dump (File   : Source_File; Show_Entities : Boolean);
   procedure Dump (Loc    : File_Location);

   procedure Set_Show_Timestamp (Show : Boolean := True);
   --  Whether timestamps should be displayed by the various dump subprograms.
   --  This should be set to False for the testsuites to get consistent
   --  results.

end Entities.Debug;
