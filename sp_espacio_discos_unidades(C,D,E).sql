
CREATE procedure [dbo].[sp_espacio_discos] 
as
begin

DECLARE
      @hr int,
      @fso int,
      @drive char(1),
      @odrive int,
      @TotalSize varchar(20),
      @MB bigint
     
      SET @MB = 1048576

      CREATE TABLE #drives (--bdnom varchar(50),
	  drive char(1),
      FreeSpace int NULL,
      TotalSize int NULL,
	  primary key (/*bdnom,*/ drive))

      INSERT #drives(drive,FreeSpace)

	  EXEC master.dbo.xp_fixeddrives
	  
      EXEC @hr=sp_OACreate 'Scripting.FileSystemObject',@fso OUT
--	  print cast(@hr as varchar(20))+'--'+cast(@fso as varchar(20))
      IF @hr <> 0 EXEC sp_OAGetErrorInfo @fso

      DECLARE dcur CURSOR LOCAL FAST_FORWARD
      FOR SELECT drive from #drives
	        ORDER by drive

      OPEN dcur
      FETCH NEXT FROM dcur INTO @drive
      WHILE @@FETCH_STATUS=0
      BEGIN
         EXEC @hr = sp_OAMethod @fso,'GetDrive', @odrive OUT, @drive
         IF @hr <> 0 EXEC sp_OAGetErrorInfo @fso
         EXEC @hr = sp_OAGetProperty @odrive,'TotalSize', @TotalSize OUT
         IF @hr <> 0 EXEC sp_OAGetErrorInfo @odrive
         --
         UPDATE #drives
         SET TotalSize=@TotalSize/@MB
         WHERE drive=@drive
         FETCH NEXT FROM dcur INTO @drive
      END
      CLOSE dcur
      DEALLOCATE dcur

      EXEC @hr=sp_OADestroy @fso
      IF @hr <> 0 EXEC sp_OAGetErrorInfo @fso

	  insert into LANDINGDEV..tb_espacio_disco 
	  select srv='SERACBI', fecha=GETDATE(),* from #drives
	  drop table #drives
end
GO








