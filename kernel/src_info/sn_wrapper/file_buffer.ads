--  This package is used to preload text files into the memory.
--  It provides ability for fast getting arbitrary line from that
--  preloaded file.
--  Also it transforms ASCII.HT characters to a sequence of spaces
--  using this rule:

with SN; use SN;

package File_Buffer is

   A : Segment;

   procedure Init (File_Name : String);
   --  Preloads specified file. Exceptions from Ada.Text_IO for
   --  Open/Close procedures can be raised in a case of IO errors.

   procedure Get_Line
     (Line   : in  Integer;
      Buffer : out SN.String_Access;
      Slice  : out Segment);
   --  Returns specified line from preloaded file.
   --  Result is in Buffer.all (Slice.First .. Slice.Last).
   --  User should not free Buffer by (s)heself.

   procedure Done;
   --  Signals that preloaded text file is not needed any more.

end File_Buffer;
