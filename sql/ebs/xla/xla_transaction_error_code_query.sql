/*==============================================================================
File:        xla/xla_transaction_error_code_query.sql
Purpose:     Identify header/line level rejection code of SLA accounting events
Context:     Oracle EBS R12.2.12 (module: XLA)
Key Tables:  apps.xla_transaction_entities_upg (xte), apps.xla_events (evt), apps.xla_accounting_errors (xlaer)
Owner:       PAWOJ95 | Created: 2025-08-21 | Last-Updated: 2025-09-26
Notes:       Read-only select
==============================================================================*/

SELECT
    xte.application_id,
    fat.application_name AS journal_source,
    gl.name              AS ledger_name,
    gp.period_name       AS period_name,
    evt.event_date,
    NVL(ei.transaction_source, 'Project Revenue') AS transaction_source,
    xet.name             AS event_type_name,
    xte.transaction_number,

    /* header-level errors (AE_LINE_NUM is null/0) */
    LISTAGG(DISTINCT CASE
              WHEN NVL(xlaer.ae_line_num, 0) = 0
              THEN TO_CHAR(xlaer.message_number)
            END, ', ')
      WITHIN GROUP (ORDER BY
            CASE WHEN NVL(xlaer.ae_line_num, 0) = 0 THEN xlaer.message_number END
      ) AS event_header_error_code,

    /* line-level errors (AE_LINE_NUM > 0) */
    LISTAGG(DISTINCT CASE
              WHEN NVL(xlaer.ae_line_num, 0) > 0
              THEN TO_CHAR(xlaer.message_number)
            END, ', ')
      WITHIN GROUP (ORDER BY
            CASE WHEN NVL(xlaer.ae_line_num, 0) > 0 THEN xlaer.message_number END
      ) AS event_line_error_code

FROM apps.xla_transaction_entities_upg xte
LEFT JOIN apps.xla_events            evt
       ON evt.entity_id = xte.entity_id
LEFT JOIN apps.xla_accounting_errors xlaer
       ON xlaer.event_id = evt.event_id
LEFT JOIN apps.xla_event_types_tl    xet
       ON xet.event_type_code = evt.event_type_code
      AND xet.language = 'US'
LEFT JOIN apps.fnd_application_tl    fat
       ON fat.application_id = xte.application_id
      AND fat.language = 'US'

/* Ledger & Period */
LEFT JOIN apps.xla_ae_headers        xah
       ON xah.event_id = evt.event_id
LEFT JOIN apps.gl_ledgers            gl
       ON gl.ledger_id = xah.ledger_id
LEFT JOIN apps.gl_periods            gp
       ON gp.period_set_name = gl.period_set_name
      AND TRUNC(xah.accounting_date) BETWEEN TRUNC(gp.start_date) AND TRUNC(gp.end_date)

/* Map transaction_number -> PA expenditure item */
LEFT JOIN apps.pa_expenditure_items_all ei
       ON ei.expenditure_item_id =
          TO_NUMBER(xte.transaction_number DEFAULT NULL ON CONVERSION ERROR)

WHERE 
    evt.event_id IS NOT NULL
AND xlaer.message_number IS NOT NULL
--AND xte.transaction_number = '124543353' -- TRANSACTION NUMBER FILTER
AND gl.name = 'BE BA PL' -- ledger name filter
--AND gp.period_name = 'NOV-22' -- period name filter
GROUP BY
    xte.application_id,
    fat.application_name,
    gl.name,
    gp.period_name,
    evt.event_date,
    ei.transaction_source,
    xet.name,
    xte.transaction_number
ORDER BY
    journal_source, ledger_name, event_date, event_type_name, transaction_number;