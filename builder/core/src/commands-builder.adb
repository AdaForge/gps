------------------------------------------------------------------------------
--                                  G P S                                   --
--                                                                          --
--                     Copyright (C) 2003-2013, AdaCore                     --
--                                                                          --
-- This is free software;  you can redistribute it  and/or modify it  under --
-- terms of the  GNU General Public License as published  by the Free Soft- --
-- ware  Foundation;  either version 3,  or (at your option) any later ver- --
-- sion.  This software is distributed in the hope  that it will be useful, --
-- but WITHOUT ANY WARRANTY;  without even the implied warranty of MERCHAN- --
-- TABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public --
-- License for  more details.  You should have  received  a copy of the GNU --
-- General  Public  License  distributed  with  this  software;   see  file --
-- COPYING3.  If not, go to http://www.gnu.org/licenses for a complete copy --
-- of the license.                                                          --
------------------------------------------------------------------------------

with Ada.Strings;                      use Ada.Strings;

with GNAT.OS_Lib;                      use GNAT.OS_Lib;
with GPS.Kernel.Messages;              use GPS.Kernel.Messages;
with GPS.Kernel.Task_Manager;          use GPS.Kernel.Task_Manager;
with GPS.Kernel.Preferences;           use GPS.Kernel.Preferences;

with Gtk.Text_View;                    use Gtk.Text_View;
with Gtkada.MDI;                       use Gtkada.MDI;

with GPS.Kernel;                       use GPS.Kernel;
with GPS.Kernel.Console;               use GPS.Kernel.Console;
with GPS.Kernel.Interactive;           use GPS.Kernel.Interactive;
with GPS.Kernel.MDI;                   use GPS.Kernel.MDI;
with GPS.Kernel.Messages.Legacy;       use GPS.Kernel.Messages.Legacy;
with GPS.Intl;                         use GPS.Intl;

with GPS.Kernel.Timeout;        use GPS.Kernel.Timeout;
with GPS.Tools_Output;          use GPS.Tools_Output;

package body Commands.Builder is

   Shell_Env : constant String := Getenv ("SHELL").all;

   type Build_Callback_Data is new Callback_Data_Record with record
      Target_Name   : Unbounded_String;
      --  The name of the target being built

      Mode_Name     : Unbounded_String;
      --  The name of the mode being built

      Category_Name : Unbounded_String;
      --  The name of the messages category to create messages in messages
      --  container.

      Background : Boolean := False;
      --  Whether this is a background build

      Shadow : Boolean := False;
      --  Whether this is a Shadow build

      Is_A_Run : Boolean := False;
      --  Whether this is a run build

      Background_Env : Extending_Environment;
      --  The extending environment created for the purpose of running this
      --  target.

      Output_Parser  : Tools_Output_Parser_Access;
      --  Chain of output parsers

      Builder        : Builder_Context;
   end record;

   type Build_Callback_Data_Access is access all Build_Callback_Data'Class;
   overriding procedure Destroy (Data : in out Build_Callback_Data);

   -----------------------
   -- Local subprograms --
   -----------------------

   procedure Build_Callback (Data : Process_Data; Output : String);
   --  Callback for the build output

   procedure End_Build_Callback (Data : Process_Data; Status : Integer);
   --  Called at the end of the build

   -------------
   -- Destroy --
   -------------

   overriding procedure Destroy (Data : in out Build_Callback_Data) is
   begin
      if Data.Output_Parser /= null then
         Free (Data.Output_Parser);
      end if;
   end Destroy;

   -----------------------
   -- Get_Build_Console --
   -----------------------

   function Get_Build_Console
     (Kernel              : GPS.Kernel.Kernel_Handle;
      Shadow              : Boolean;
      Background          : Boolean;
      Create_If_Not_Exist : Boolean;
      New_Console_Name    : String := "") return Interactive_Console
   is
      Console : Interactive_Console;
   begin
      if New_Console_Name /= "" then
         Console := Create_Interactive_Console
           (Kernel              => Kernel,
            Title               => New_Console_Name,
            History             => "interactive",
            Create_If_Not_Exist => True,
            Module              => null,
            Force_Create        => False,
            ANSI_Support        => True,
            Accept_Input        => True);

         Modify_Font (Get_View (Console), View_Fixed_Font.Get_Pref);

         return Console;
      end if;

      if Background then
         return Create_Interactive_Console
           (Kernel              => Kernel,
            Title               => -"Background Builds",
            History             => "interactive",
            Create_If_Not_Exist => Create_If_Not_Exist,
            Module              => null,
            Force_Create        => False,
            Accept_Input        => False);

      elsif Shadow then
         return Create_Interactive_Console
           (Kernel              => Kernel,
            Title               => -"Auxiliary Builds",
            History             => "interactive",
            Create_If_Not_Exist => Create_If_Not_Exist,
            Module              => null,
            Force_Create        => False,
            Accept_Input        => False);
      else
         return Get_Console (Kernel);
      end if;
   end Get_Build_Console;

   ------------------------
   -- End_Build_Callback --
   ------------------------

   procedure End_Build_Callback (Data : Process_Data; Status : Integer) is
      Build_Data : Build_Callback_Data
                     renames Build_Callback_Data (Data.Callback_Data.all);

   begin
      if Build_Data.Output_Parser /= null then
         Build_Data.Output_Parser.End_Of_Stream (Status, Data.Command);
      end if;

      if Build_Data.Is_A_Run then
         --  Nothing to do for runs.
         return;
      end if;

      --  Raise the messages window is compilation was unsuccessful
      --  and no error was parsed. See D914-005

      if Category_Count (Data.Kernel, To_String (Build_Data.Category_Name)) = 0
        and then Status /= 0
        and then not Build_Data.Background
      then
         Data.Kernel.Raise_Console;
      end if;

      Destroy (Build_Data.Background_Env);

      if Build_Data.Background then
         --  We remove the previous background build data messages only when
         --  the new background build is completed.

         Get_Messages_Container (Data.Kernel).Remove_Category
           (Previous_Background_Build_Id (Build_Data.Builder),
            Background_Message_Flags);

         Background_Build_Finished (Build_Data.Builder);
      end if;

      --  ??? should also pass the Status value to Compilation_Finished
      --  and to the corresponding hook

      Compilation_Finished
        (Data.Kernel,
         To_String (Build_Data.Category_Name),
         To_String (Build_Data.Target_Name),
         To_String (Build_Data.Mode_Name),
         Build_Data.Shadow,
         Build_Data.Background,
         Status);
   end End_Build_Callback;

   --------------------
   -- Build_Callback --
   --------------------

   procedure Build_Callback (Data : Process_Data; Output : String) is
      Build_Data : Build_Callback_Data
        renames Build_Callback_Data (Data.Callback_Data.all);
   begin
      if Build_Data.Output_Parser /= null then
         Build_Data.Output_Parser.Parse_Standard_Output (Output, Data.Command);
      end if;
   end Build_Callback;

   --------------------------
   -- Launch_Build_Command --
   --------------------------

   procedure Launch_Build_Command
     (Kernel           : GPS.Kernel.Kernel_Handle;
      CL               : Arg_List;
      Server           : Server_Type;
      Synchronous      : Boolean;
      Use_Shell        : Boolean;
      Console          : Interactive_Console;
      Directory        : Virtual_File;
      Builder          : Builder_Context;
      Background_Env   : Extending_Environment;
      Target_Name      : String;
      Mode             : String;
      Category_Name    : Unbounded_String;
      Quiet            : Boolean;
      Shadow           : Boolean;
      Background       : Boolean;
      Is_Run           : Boolean)
   is
      Data     : Build_Callback_Data_Access;
      CL2      : Arg_List;
      Success  : Boolean := False;
      Cmd_Name : Unbounded_String;
      Show_Command : Boolean;
      Created_Command : Scheduled_Command_Access;
   begin
      Data := new Build_Callback_Data;
      Data.Target_Name := To_Unbounded_String (Target_Name);
      Data.Builder := Builder;
      Data.Category_Name  := Category_Name;
      Data.Mode_Name      := To_Unbounded_String (Mode);
      Data.Shadow         := Shadow;
      Data.Background     := Background;
      Data.Background_Env := Background_Env;
      Data.Is_A_Run       := Is_Run;
      Data.Output_Parser  := New_Parser_Chain (Target_Name);

      Show_Command := not Background and not Quiet;

      if not Is_Run and then not Background then
         --  If we are starting a "real" build, remove messages from the
         --  current background build
         Get_Messages_Container (Kernel).Remove_Category
           (Data.Builder.Previous_Background_Build_Id,
            Background_Message_Flags);
      end if;

      if not Shadow and Show_Command then
         if Is_Run then
            Clear (Console);
            Raise_Child (Find_MDI_Child (Get_MDI (Kernel), Console),
                         Give_Focus => True);
         else
            Raise_Console (Kernel);
         end if;
      end if;

      if Is_Run
        or else Compilation_Starting
          (Handle     => Kernel,
           Category   => To_String (Category_Name),
           Quiet      => Quiet,
           Shadow     => Shadow,
           Background => Background)
      then
         if not Quiet then
            Append_To_Build_Output
              (Builder,
               To_Display_String (CL), Target_Name,
               Shadow, Background);
         end if;

         if Mode /= "default" then
            Cmd_Name := Data.Target_Name & " (" & Data.Mode_Name & ")";
         else
            Cmd_Name := Data.Target_Name;
         end if;

         if Use_Shell
           and then Shell_Env /= ""
           and then Is_Local (Server)
         then
            Append_Argument (CL2, Shell_Env, One_Arg);
            Append_Argument (CL2, "-c", One_Arg);
            Append_Argument (CL2, To_Display_String (CL), One_Arg);
         else
            CL2 := CL;
         end if;

         Launch_Process
           (Kernel,
            CL                   => CL2,
            Server               => Server,
            Console              => Console,
            Show_Command         => Show_Command,
            Show_Output          => False,
            Callback_Data        => Data.all'Access,
            Success              => Success,
            Line_By_Line         => False,
            Directory            => Directory,
            Callback             => Build_Callback'Access,
            Exit_Cb              => End_Build_Callback'Access,
            Show_In_Task_Manager => not Background,
            Name_In_Task_Manager => To_String (Cmd_Name),
            Synchronous          => Synchronous,
            Show_Exit_Status     => not (Shadow
              or else Background
              or else Quiet),
            Block_Exit           => not (Shadow
              or else Background
              or else Quiet),
            Created_Command      => Created_Command);

         --  ??? check value of Success

         if Success and then Background then
            Background_Build_Started
              (Builder, Command_Access (Created_Command));
         end if;
      end if;

   end Launch_Build_Command;

end Commands.Builder;
