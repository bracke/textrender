with Ada.Command_Line;

with AUnit;
with AUnit.Reporter.Text;
with AUnit.Run;
with All_Suites;

--  Runs the suite and, unlike AUnit's plain runner, says so in the exit status.
--
--  Test_Runner reports success however many assertions failed, so a build server
--  sees a green job while the log underneath it lists failures. That is worse
--  than having no tests at all: it is a signal that reads as proof and is not
--  one. A macOS run reported a failing colour-font assertion and passed anyway.
procedure Tests is
   function Runner is new AUnit.Run.Test_Runner_With_Status (All_Suites.Suite);
   Reporter : AUnit.Reporter.Text.Text_Reporter;
   Status   : AUnit.Status;
   use type AUnit.Status;
begin
   Status := Runner (Reporter);
   Ada.Command_Line.Set_Exit_Status
     (if Status = AUnit.Success
      then Ada.Command_Line.Success
      else Ada.Command_Line.Failure);
end Tests;
