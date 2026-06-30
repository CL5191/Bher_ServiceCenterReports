$Script:ReportConfig = @{
    Graph = @{
        TenantId                    = "a19f8d53-91d3-403c-9b6c-2033f5ab3b9e"
        ClientId                    = "0904f7dd-c8a5-4b5c-a70a-37d4152af4d1"
        CertificateThumbprint       = "C2116152E86854B88017A1B605B8B14377C53969"
        Scope                       = "https://graph.microsoft.com/.default"
        MaxRetryCount               = 5
        InitialRetryDelaySeconds    = 2
    }

    Reporting = @{
        DaysDelayForDataFinalization = 1
        SLASeconds                   = 60
        OutputRoot                   = Join-Path $PSScriptRoot "..\\Output"
        ReportsPath                  = Join-Path $PSScriptRoot "..\\Output\\Reports"
        LogsPath                     = Join-Path $PSScriptRoot "..\\Output\\Logs"
        ArchivePath                  = Join-Path $PSScriptRoot "..\\Output\\Archive"
        PdfGenerator                 = "wkhtmltopdf"
    }

    Email = @{
        SenderMailbox = "chad_logan@mascohq.com"
        ToRecipients  = @("MASCO_SG_Behr_TeamsServiceCenterReporting@mascohq.com")
        SubjectPrefix = "Service Center Call Queue Report"
    }

    EmailGroups = @{
        StandardReports  = @("MASCO_SG_Behr_TeamsServiceCenterReporting@mascohq.com")
        SolutionsCenter  = @("MASCO_SG_Behr_TeamsSolutionCenterReporting@mascohq.com")
    }

    Files = @{
        QueueMapFile = Join-Path $PSScriptRoot "queues.json"
    }
}

function Get-ReportConfig {
    return $Script:ReportConfig
}
