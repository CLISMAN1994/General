

CREATE Procedure [dbo].[sp_alerta_disco_lleno] 
as
Begin

select 
a.srv, 
a.drive, 
FreeSpaceGB=FreeSpace/1024, 
FreeSpace, 
TotalSizeGB=TotalSize/1024, 
TotalSize, 
_PorcLibre=(FreeSpace/TotalSize)*100,
fecha 
into #tmp_discosllenos
from LANDINGDEV..tb_espacio_disco a 
inner join 
(select srv, drive, fecha_max=max(fecha) 
	from LANDINGDEV..tb_espacio_disco 
	group by srv, drive) b on a.srv=b.srv and a.drive=b.drive and a.fecha=b.fecha_max 
where (FreeSpace/TotalSize)*100<10
order by 1,2,8 

/* ENVIO DE EMAIL PARA CLIENTES SIN RUC */
	DECLARE @wCountCli INT
	DECLARE @wMsgCli VARCHAR(100)
	DECLARE @xmlCli NVARCHAR(MAX)
	DECLARE @body_qryCli NVARCHAR(MAX)
	
	SELECT @wCountCli = COUNT(*) FROM #tmp_discosllenos 

	SET @wMsgCli = '<p>ALERTA DE LÍMITE DE CAPACIDAD DE DISCOS</p>'
	/* BOF: HTML ::  CREAR UN HTML DE LA TABLA*/
	
	SET @xmlCli = CAST(( SELECT DISTINCT VC.srv AS 'td','', VC.drive AS 'td','', convert(decimal(18,2),ISNULL(VC.FreeSpaceGB,0)) AS 'td','', 
							convert(decimal(18,2),ISNULL(VC.TotalSizeGB,0)) AS 'td','', convert(decimal(18,2),ISNULL(VC._PorcLibre,0)) AS 'td','', ISNULL(VC.fecha,'') AS 'td'
								FROM #tmp_discosllenos AS VC 

								FOR XML PATH('tr'), ELEMENTS ) AS NVARCHAR(MAX))
	set @body_qryCli='<style>table tr td {font-size:12px;} 
							table#tblRsp tr:nth-child(even){ background-color:#eee;} 
							table#tblRsp tr:nth-child(odd){ background-color:#fff;}
							</style>
					<table id="tblRsp" border="1" cellpadding="6" cellspacing="6" style="border-collapse:collapse;">
						<tr><th style="background-color: #b23535;" >
							<b><span style="color: #ffffff;">Servidor</span></b>
							</th>
						<th style="background-color: #b23535;" >
							<b><span style="color: #ffffff;">Drive</span></b>
							</th>
						<th style="background-color: #b23535;" >
							<b><span style="color: #ffffff;">Libre(GB)</span></b>
							</th>
						<th style="background-color: #b23535;" >
							<b><span style="color: #ffffff;">Total(GB)</span></b>
							</th>
						<th style="background-color: #b23535;" >
							<b><span style="color: #ffffff;">%Dispo.</span></b>
							</th>
						<th style="background-color: #b23535;" >
							<b><span style="color: #ffffff;">Fecha-Hora</span></b>
							</th>
						</tr>' + @xmlCli +'</table>
						<br /><br /> Atte. 
						<br /> Equipo TI. 
						<br /> -------------------------- 
						<br /> Antes de imprimir este mensaje, piensa!, Realmente lo necesitas?'
	
	/* EOF: HTML ::  CREAR UN HTML DE LA TABLA */
	DECLARE @wMsgBodyCli varchar(max)
	set @wMsgBodyCli = @wMsgCli + @body_qryCli

	IF (@wCountCli>0)
		BEGIN
			EXEC msdb.dbo.sp_send_dbmail
			@profile_name = 'Administrador de Software',
			@recipients = 'desarrollo2@acfarma.com; clabrin@acfarma.com',
			@copy_recipients = 'asaplicaciones@acfarma.com; informatica@acfarma.com',
			@blind_copy_recipients = '',
			@subject = 'Alerta : Capacidad de Discos',
			@body = @wMsgBodyCli,
			@body_format = 'HTML',
			@exclude_query_output=1
		END 

	drop table #tmp_discosllenos

End
GO


