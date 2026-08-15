/**
 * @Description: Broker Snapshot DocGen Provider. Supplies Account merge fields (plus the
 * lost-opportunity and top-opportunity child loops) to the Portwood DocGen engine for the
 * "Broker Snapshot" Word template, replacing the field set previously hard-coded in
 * WT_BrokerSnapshotDynamic.page / WT_BrokerSnapshotExternal.page.
 *
 * Merge tag naming: section prefixes and field names are intentionally short (e.g.
 * "scard.PolComFund" rather than "scorecard.PolicyCommissionFunding") to keep the Word
 * template's {tag} text compact. The full old-name -> short-tag mapping is documented in the
 * Broker Snapshot Technical Design document (docs/templates) — update both together if a tag
 * ever needs to change, since the Word template's {tags} must match these map keys exactly.
 */
global with sharing class WT_BrokerSnapshotDocGenProvider implements portwoodglobal.DocGenDataProvider {
    global Map<String, Object> getData(Id recordId) {
        // recordId is the ID of the Account record.
        List<Account> listAccountRecords = [
            SELECT
                Id, Name, Website, Account_Executive_formula__c, FIRST_Competitor_Usage__c, FIRST_Competitor__c,
                Fee_Reduction_Approver__c, Servicing_Team_Lookup__r.Contact_1__r.Email, Servicing_Team_Lookup__r.Contact_1__r.Phone,
                Funding_Method__c, Funding_Party__c, WT_Funding_Delay_Configuration__c, WT_Policy_Commission_Funding__c,
                e_notice_delivery__c, Individual_User_Log_ins__c, WT_Global_User_Log_In__c, Agency_Software_System__c,
                Allow_CRB_Quotes__c, Personal_Lines_Set_Up__c, Quoting_Authority__c,
                E_Complete_Set_Up__c, Auto_Book_with_Down_Payment__c, Auto_E_Signature__c, WT_e_Complete_Co_Branding__c,
                Allow_FIFC_to_Collect_DP__c, Ecomplete_Quotes_YTD__c, Allow_FIFC_to_Collect_PIF__c, Default_To_FIFC_Collects__c,
                First_Rewards__c, New_York_Service_Agreement__c, Fee_Payment_Frequency__c, Pre_Paid_Agreement__c,
                Pre_Paid_Income__c, Estimated_Bonus_Amount__c, Late_Fee_and_Loss_Sharing__c, Estimated_Late_Fee_Amount__c,
                Bonus_Structure__c,
                WT_Number_Of_Referral__c, Agency_Lending_Closed_with_Wintrust__c, WT_Existing_Deposit__c,
                WT_LND_Development_Program__c, WT_Agency_Interest_in_Sports_Tickets__c, Favorite_Team__c, WT_Agency_Sponsorships__c,
                Est_Amount_Financed__c, TTM_Volume__c, YTD_Loans_Current_Year__c, YTD_Loans_Prior_Year__c,
                YTD_Volume_Current_Year__c, YTD_Volume_Prior_Year__c, YTD_Vol_Variance__c,
                YTD_Fee_Income_Current_Year__c, YTD_Fee_Income_Prior_Year__c,
                Prior_Year_YE_Loans__c, Prior_Year_YE_Volume__c, Prior_Year_YE_Fee_Income__c,
                X2_Year_prior_YE_Loans__c, X2_Year_prior_YE_Volume__c, X2_Year_prior_YE_Fee_Income__c,
                YTD_Write_Offs_Current_Year__c, WT_2025_YE_Write_Offs__c, X2024_YE_Write_offs__c
            FROM Account
            WHERE Id = :recordId
            WITH USER_MODE
        ];

        if (listAccountRecords.isEmpty()) {
            return new Map<String, Object>();
        }
        Account accountRecord = listAccountRecords.get(0);

        // Top-level map keyed by short section codes; each value is itself a Map of short
        // field codes -> raw typed values. Raw values (Boolean/Decimal/Date/String) are
        // returned as-is — number/currency/percent/checkbox/date formatting is applied by
        // the Word template's {tag:format} specifiers, not here, so the same provider works
        // no matter how the template chooses to display a value.
        Map<String, Object> mapMergeData = new Map<String, Object>();
        mapMergeData.put('gen', buildGeneralMap(accountRecord));
        mapMergeData.put('scard', buildScorecardMap(accountRecord));
        mapMergeData.put('ecomp', buildECompleteMap(accountRecord));
        mapMergeData.put('comp', buildCompensationMap(accountRecord));
        mapMergeData.put('xsell', buildCrossSellingMap(accountRecord));
        mapMergeData.put('addval', buildAddedValueMap(accountRecord));
        mapMergeData.put('prod', buildProductionMap(accountRecord));
        mapMergeData.put('histprod', buildHistoricalProductionMap(accountRecord));
        mapMergeData.put('lostAccts', buildOpportunityLoopMap(getLostOpportunities(recordId)));
        mapMergeData.put('topOpps', buildOpportunityLoopMap(getTopOpportunities(recordId)));

        return mapMergeData;
    }

    private Map<String, Object> buildGeneralMap(Account accountRecord) {
        return new Map<String, Object>{
            'AcctName' => accountRecord.Name,
            'Web' => accountRecord.Website,
            'AcExecName' => accountRecord.Account_Executive_formula__c,
            'CompUsage' => accountRecord.FIRST_Competitor_Usage__c,
            'CompName' => accountRecord.FIRST_Competitor__c,
            'FeeRedApp' => accountRecord.Fee_Reduction_Approver__c,
            // Safe-navigation (?.) because the Servicing_Team_Lookup__c / Contact_1__c chain
            // is optional — an Account without a servicing team on file should still merge
            // cleanly with blank Account Executive contact fields instead of erroring.
            'AcExecEmail' => accountRecord.Servicing_Team_Lookup__r?.Contact_1__r?.Email,
            'AcExecPhone' => accountRecord.Servicing_Team_Lookup__r?.Contact_1__r?.Phone
        };
    }

    private Map<String, Object> buildScorecardMap(Account accountRecord) {
        return new Map<String, Object>{
            'FundMethod' => accountRecord.Funding_Method__c,
            'FundParty' => accountRecord.Funding_Party__c,
            'FundDelay' => accountRecord.WT_Funding_Delay_Configuration__c,
            'PolComFund' => accountRecord.WT_Policy_Commission_Funding__c,
            'ENoticeDel' => accountRecord.e_notice_delivery__c,
            'IndUserLogin' => accountRecord.Individual_User_Log_ins__c,
            'GlblUserLogin' => accountRecord.WT_Global_User_Log_In__c,
            'AgSoftInteg' => accountRecord.Agency_Software_System__c,
            'CrbSetup' => accountRecord.Allow_CRB_Quotes__c,
            'PersLines' => accountRecord.Personal_Lines_Set_Up__c,
            'QuoteAuth' => accountRecord.Quoting_Authority__c
        };
    }

    private Map<String, Object> buildECompleteMap(Account accountRecord) {
        return new Map<String, Object>{
            'EComp' => accountRecord.E_Complete_Set_Up__c,
            'AutoBook' => accountRecord.Auto_Book_with_Down_Payment__c,
            'AutoSign' => accountRecord.Auto_E_Signature__c,
            'ECompCoBrand' => accountRecord.WT_e_Complete_Co_Branding__c,
            'FifCollDp' => accountRecord.Allow_FIFC_to_Collect_DP__c,
            'ECompQtsYtd' => accountRecord.Ecomplete_Quotes_YTD__c,
            'Pif' => accountRecord.Allow_FIFC_to_Collect_PIF__c,
            'FifDefColl' => accountRecord.Default_To_FIFC_Collects__c
        };
    }

    private Map<String, Object> buildCompensationMap(Account accountRecord) {
        return new Map<String, Object>{
            'FstRewards' => accountRecord.First_Rewards__c,
            'NyServAgr' => accountRecord.New_York_Service_Agreement__c,
            'FeePayFreq' => accountRecord.Fee_Payment_Frequency__c,
            'PrePaidAgr' => accountRecord.Pre_Paid_Agreement__c,
            'PrePaidBal' => accountRecord.Pre_Paid_Income__c,
            'EstBonusAmt' => accountRecord.Estimated_Bonus_Amount__c,
            'LateFeeLoss' => accountRecord.Late_Fee_and_Loss_Sharing__c,
            'EstLateFeeAmt' => accountRecord.Estimated_Late_Fee_Amount__c,
            'Bonus' => accountRecord.Bonus_Structure__c
        };
    }

    private Map<String, Object> buildCrossSellingMap(Account accountRecord) {
        return new Map<String, Object>{
            'NumReferrals' => accountRecord.WT_Number_Of_Referral__c,
            'AgLending' => accountRecord.Agency_Lending_Closed_with_Wintrust__c,
            'BankWintrust' => accountRecord.WT_Existing_Deposit__c
        };
    }

    private Map<String, Object> buildAddedValueMap(Account accountRecord) {
        return new Map<String, Object>{
            'AgDevProg' => accountRecord.WT_LND_Development_Program__c,
            'IntSportTix' => accountRecord.WT_Agency_Interest_in_Sports_Tickets__c,
            'FavTeam' => accountRecord.Favorite_Team__c,
            'Sponsor' => accountRecord.WT_Agency_Sponsorships__c
        };
    }

    private Map<String, Object> buildProductionMap(Account accountRecord) {
        return new Map<String, Object>{
            'PotBusiness' => accountRecord.Est_Amount_Financed__c,
            'TtmVol' => accountRecord.TTM_Volume__c,
            'YtdLoanCurYr' => accountRecord.YTD_Loans_Current_Year__c,
            'YtdLoanPriorYr' => accountRecord.YTD_Loans_Prior_Year__c,
            'YtdVolCurYr' => accountRecord.YTD_Volume_Current_Year__c,
            'YtdVolPriorYr' => accountRecord.YTD_Volume_Prior_Year__c,
            'YtdVolVar' => accountRecord.YTD_Vol_Variance__c,
            'YtdFeeIncCurYr' => accountRecord.YTD_Fee_Income_Current_Year__c,
            'YtdFeeIncPriorYr' => accountRecord.YTD_Fee_Income_Prior_Year__c
        };
    }

    private Map<String, Object> buildHistoricalProductionMap(Account accountRecord) {
        return new Map<String, Object>{
            'PYeLoans' => accountRecord.Prior_Year_YE_Loans__c,
            'PYeVolume' => accountRecord.Prior_Year_YE_Volume__c,
            'PYeFeeInc' => accountRecord.Prior_Year_YE_Fee_Income__c,
            'TwoYrYeLoans' => accountRecord.X2_Year_prior_YE_Loans__c,
            'TwoYrYeVol' => accountRecord.X2_Year_prior_YE_Volume__c,
            'TwoYrYeFeeInc' => accountRecord.X2_Year_prior_YE_Fee_Income__c,
            'YtdWoCurYr' => accountRecord.YTD_Write_Offs_Current_Year__c,
            'Ye2025Wo' => accountRecord.WT_2025_YE_Write_Offs__c,
            'Ye2024Wo' => accountRecord.X2024_YE_Write_offs__c
        };
    }

    private List<Opportunity> getLostOpportunities(Id accountId) {
        return [
            SELECT Id, Name, Amount, Effective_Date__c, StageName, Lost_Reason__c
            FROM Opportunity
            WHERE (StageName = 'Lost' OR StageName = 'Lost - No Follow up')
            AND (Lost_Reason__c = 'Rates' OR Lost_Reason__c = 'Terms')
            AND AccountId = :accountId
            WITH USER_MODE
            ORDER BY Amount DESC
            LIMIT 3
        ];
    }

    private List<Opportunity> getTopOpportunities(Id accountId) {
        Date startOfCurrentYear = Date.newInstance(Date.today().year(), 1, 1);
        Date endOfCurrentYear = Date.newInstance(Date.today().year(), 12, 31);
        return [
            SELECT Id, Name, Amount, Effective_Date__c, StageName
            FROM Opportunity
            WHERE Loan_Value_Under_Threshold__c = false
            AND ((CloseDate >= :startOfCurrentYear AND CloseDate <= :endOfCurrentYear)
                 OR (Effective_Date__c >= :startOfCurrentYear AND Effective_Date__c <= :endOfCurrentYear))
            AND Amount != NULL
            AND AccountId = :accountId
            WITH USER_MODE
            ORDER BY Amount DESC
            LIMIT 5
        ];
    }

    // Shared by both loop sections (lostAccts / topOpps) — both render the same row shape,
    // so one helper keeps the Map<String,Object> "records" contract (per
    // portwoodglobal.DocGenDataProvider's documented child-loop shape) in one place.
    private Map<String, Object> buildOpportunityLoopMap(List<Opportunity> listOpportunityRecords) {
        List<Object> listOpportunityRows = new List<Object>();
        for (Opportunity opportunityRecord : listOpportunityRecords) {
            listOpportunityRows.add(
                new Map<String, Object>{
                    'Name' => opportunityRecord.Name,
                    'Amt' => opportunityRecord.Amount,
                    'EffDate' => opportunityRecord.Effective_Date__c,
                    'Stage' => opportunityRecord.StageName,
                    'LostRsn' => opportunityRecord.Lost_Reason__c
                }
            );
        }
        return new Map<String, Object>{ 'records' => listOpportunityRows, 'totalSize' => listOpportunityRows.size() };
    }

    global List<String> getFieldNames() {
        List<String> listMergeTagNames = new List<String>{
            'gen.AcctName', 'gen.Web', 'gen.AcExecName', 'gen.CompUsage', 'gen.CompName', 'gen.FeeRedApp',
            'gen.AcExecEmail', 'gen.AcExecPhone',
            'scard.FundMethod', 'scard.FundParty', 'scard.FundDelay', 'scard.PolComFund', 'scard.ENoticeDel',
            'scard.IndUserLogin', 'scard.GlblUserLogin', 'scard.AgSoftInteg', 'scard.CrbSetup', 'scard.PersLines',
            'scard.QuoteAuth',
            'ecomp.EComp', 'ecomp.AutoBook', 'ecomp.AutoSign', 'ecomp.ECompCoBrand', 'ecomp.FifCollDp',
            'ecomp.ECompQtsYtd', 'ecomp.Pif', 'ecomp.FifDefColl',
            'comp.FstRewards', 'comp.NyServAgr', 'comp.FeePayFreq', 'comp.PrePaidAgr', 'comp.PrePaidBal',
            'comp.EstBonusAmt', 'comp.LateFeeLoss', 'comp.EstLateFeeAmt', 'comp.Bonus',
            'xsell.NumReferrals', 'xsell.AgLending', 'xsell.BankWintrust',
            'addval.AgDevProg', 'addval.IntSportTix', 'addval.FavTeam', 'addval.Sponsor',
            'prod.PotBusiness', 'prod.TtmVol', 'prod.YtdLoanCurYr', 'prod.YtdLoanPriorYr', 'prod.YtdVolCurYr',
            'prod.YtdVolPriorYr', 'prod.YtdVolVar', 'prod.YtdFeeIncCurYr', 'prod.YtdFeeIncPriorYr',
            'histprod.PYeLoans', 'histprod.PYeVolume', 'histprod.PYeFeeInc', 'histprod.TwoYrYeLoans',
            'histprod.TwoYrYeVol', 'histprod.TwoYrYeFeeInc', 'histprod.YtdWoCurYr', 'histprod.Ye2025Wo',
            'histprod.Ye2024Wo',
            '#lostAccts', 'lostAccts.Name', 'lostAccts.Amt', 'lostAccts.EffDate', 'lostAccts.Stage',
            'lostAccts.LostRsn', '/lostAccts',
            '#topOpps', 'topOpps.Name', 'topOpps.Amt', 'topOpps.EffDate', 'topOpps.Stage', '/topOpps'
        };
        return listMergeTagNames;
    }
}
