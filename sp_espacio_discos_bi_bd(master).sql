
CREATE PROCEDURE [dbo].[sp_espacio_discos_bi] 
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
	  --print cast(@hr as varchar(20))+'--'+cast(@fso as varchar(20))
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

	  delete [seracbi].[landingdev].dbo.tb_temp_espacio_bi where servidor='SERACBI'
	  
	  insert into [seracbi].[landingdev].dbo.tb_temp_espacio_bi 
	  select Servidor='SERACBI', 
	  Fecha=GETDATE(),
	  Drive, 
	  FreeSpaceMB=round(FreeSpace,2), 
	  UsageSpaceMB=round(TotalSize-FreeSpace,2), 
	  TotalSizeMB=round(TotalSize,2), 
	  FreeSpaceGB=round(FreeSpace/1024,2), 
	  UsageSpaceGB=(TotalSize-FreeSpace)/1024, 
	  TotalSizeGB=round(TotalSize/1024,2) 
	  from #drives
	  drop table #drives

	  --limpiar log 
	  /************** Antes de truncar el log cambiamos el modelo de recuperación a SIMPLE *****************/
	ALTER DATABASE master 
	SET RECOVERY SIMPLE;
	
	/*** Reducimos el log de transacciones a  X MB. Lo recomendable es que no sea menor al tamaño de creación  ***/
	DBCC SHRINKFILE(mastlog, 1);

	/************** Cambiamos nuevamente el modelo de recuperación a Completo.  *****************/
	ALTER DATABASE master 
	SET RECOVERY FULL;
	
	-------------------------------------------------------------------------------------------------
	-----------------------------ACTUALIZA TABLA DE ESPACIOS DE BD------------------------------------
	delete [seracbi].[landingdev].dbo.tb_temp_espacio_bd where Servidor='SERACBI' and Instancia=(select @@servicename)
	
	insert into [seracbi].[landingdev].dbo.tb_temp_espacio_bd
	select 
	Servidor='SERACBI',
	Instancia=(select @@servicename),
    [Base de Datos]=name, 
	Estado=db.state_desc, 
    round(sum(case when type = 0 then mf.size else 0 end),2) DatosMB,
    round(sum(case when type = 1 then mf.size else 0 end),2) LogMB,
	Round(sum(case when type = 0 then mf.size else 0 end)+sum(case when type = 1 then mf.size else 0 end),2) as TotalMB,
	round(sum(case when type = 0 then mf.size else 0 end)/1024,2) DatosGB, 
	round(sum(case when type = 1 then mf.size else 0 end)/1024,2) LogGB,
	round((sum(case when type = 0 then mf.size else 0 end)/1024)+(sum(case when type = 1 then mf.size else 0 end)/1024),2) as TotalGB
	from sys.databases db
	inner join (select database_id, type, size * 8.0 / 1024 size
		from sys.master_files) mf ON mf.database_id = db.database_id
	group by name, db.state_desc

	insert into LANDINGDEV..tb_temp_ram_bi
	select Servidor='SERACBI',
	MemoriaEnUso_SQL=((T1.physical_memory_in_use_kb + T1.large_page_allocations_kb + T1.locked_page_allocations_kb)/1024)/1024.00,
	MemoriaEnUso_OtrosProgramas=(((T2.total_physical_memory_kb - T2.available_physical_memory_kb)/1024)/1024.00)-(((T1.physical_memory_in_use_kb + T1.large_page_allocations_kb + T1.locked_page_allocations_kb)/1024)/1024.00), 
	MemoriaEnUso_Total=((T2.total_physical_memory_kb - T2.available_physical_memory_kb)/1024)/1024.00, 
	MemoriaDisponible_Total=(T2.available_physical_memory_kb/1024)/1024.00, 
	MemoriaTotal_Servidor=(t2.total_physical_memory_kb/1024)/1024.00, 
	GETDATE() 
	from sys.dm_os_process_memory as T1
	cross join sys.dm_os_sys_memory as T2

	-------------------------------------------------------------------------------------------------
	----------------------------- ACTUALIZA TABLA DE CONSUMO DE PROCESADOR ------------------------------------
	-- CPU Usage SQL Server 

	DECLARE @ts_now bigint = (SELECT cpu_ticks/(cpu_ticks/ms_ticks) FROM sys.dm_os_sys_info);  
	DECLARE @Timestamp_ult bigint  

	select @Timestamp_ult=MAX([Timestamp]) 
	from LANDINGDEV..tb_temp_procesador_bi 
	where Servidor='SERACBI' and convert(varchar(10),[Event Time],103)=convert(varchar(10),GETDATE(),103)

	Insert Into LANDINGDEV..tb_temp_procesador_bi 
	SELECT TOP(1000)  
	'SERACBI', 
	[record_id], 
	SQLProcessUtilization AS [SQL Server Process CPU Utilization],  
				   SystemIdle AS [System Idle Process],  
				   100 - SystemIdle - SQLProcessUtilization AS [Other Process CPU Utilization],  
				   DATEADD(ms, -1 * (@ts_now - [timestamp]), GETDATE()) AS [Event Time], [timestamp]
	FROM (  
		SELECT record.value('(./Record/@id)[1]', 'int') AS record_id,  
		record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS [SystemIdle],  
		record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') AS [SQLProcessUtilization], [timestamp]  
		FROM (
			SELECT [timestamp], CONVERT(xml, record) AS [record]  
			FROM sys.dm_os_ring_buffers  
			WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'  
			AND record LIKE '%<SystemHealth>%') AS x  
		) AS y  
	WHERE y.[timestamp]>@Timestamp_ult OR @Timestamp_ult is NULL
	ORDER BY record_id DESC; 

end
GO

select * from LANDINGDEV..tb_temp_procesador_bi 
select * from [seracbi].[landingdev].dbo.tb_temp_espacio_bd

