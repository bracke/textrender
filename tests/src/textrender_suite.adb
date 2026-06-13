with Textrender.BasicTests;

package body Textrender_Suite is

   function Suite return Access_Test_Suite is
      Ret : constant Access_Test_Suite := new Test_Suite;
   begin
      Ret.Add_Test (new Textrender.BasicTests.Textrender_Basic_Case);

      return Ret;
   end Suite;

end Textrender_Suite;