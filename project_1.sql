-- WARSZTAT

USE financial3_46;

# Struktura bazy

-- Klucze głowne w tabelach
DESCRIBE account;
DESCRIBE card;
DESCRIBE client;
DESCRIBE disp;
DESCRIBE district;
DESCRIBE loan;
DESCRIBE `order`;
DESCRIBE trans;

# Historia udzielanych kredytów

-- Podsumowanie udzielanych kredytów w wymiarach: rok/kwartał/miesiąc, rok/kwartał, rok, sumarycznie

SELECT * FROM loan;

SELECT
    sum(amount) as sum_kwota_pozyczek
,   avg(amount) as avg_kwota_pozyczki
,   count(amount) as liczba_udzielonych_pozyczek
,   EXTRACT(YEAR FROM date) AS rok
,   EXTRACT(QUARTER FROM date) AS kwartal
,   EXTRACT(MONTH FROM date) AS miesiac
FROM loan
GROUP BY
    rok, kwartal, miesiac
    WITH ROLLUP;

# Status pożyczki
-- Które pożyczki zostały spłacone ? -- > 606

SELECT
    status
,   count(status)
FROM loan
GROUP BY status; -- > ststus A,C pożyczki spłacone, status B,D pożyczki niespłacone

# Analiza kont
-- uszeregowanie kont, dla spłaconych pożyczek wg kryteriów: liczba udzielonych pożyczek (malejąco), kwota udzielonych pożyczek (malejąco), średnia kwota pożyczki

WITH account_analysis as (
    SELECT
        account_id
    ,   count(account_id) as count_accound_id
    ,   sum(amount) as sum_amount
    ,   avg(amount) as avg_amount
    FROM
        loan
    WHERE
        status = 'A' OR status = 'C'
    GROUP BY account_id
    )
SELECT
    *
,   ROW_NUMBER() over (ORDER BY count_accound_id DESC) AS rank_count_accound_id
,   ROW_NUMBER() over (ORDER BY sum_amount DESC) AS rank_sum_amount
FROM account_analysis;

# Spłacone pożyczki
-- Ilość spłaconych pożyczek w podziale na płeć

DROP TABLE IF EXISTS tmp_results;
CREATE TEMPORARY TABLE tmp_results AS
SELECT
    count(l.account_id) as count_repaid_loans
,   c.gender
, sum(amount) as sum_amount
FROM
    loan l
INNER JOIN
        account a USING (account_id)
INNER JOIN
        disp d USING (account_id)
INNER JOIN
        client c USING (client_id)
WHERE
    l.status in ('A','C')
AND
    d.type = 'OWNER'
GROUP BY c.gender;

-- sprawdzenie poprawności
WITH cte as (
    SELECT sum(amount) as amount
    FROM loan as l
    WHERE l.status IN ('A', 'C')
)
SELECT (SELECT SUM(sum_amount) FROM tmp_results) - (SELECT amount FROM cte); -- ma być 0

# Analiza klienta cz. 1

DROP TABLE IF EXISTS tmp_analysis;
CREATE TEMPORARY TABLE tmp_analysis AS
SELECT
    c.gender
,   2021 - extract(year from birth_date) as age
,    sum(l.amount) as amount
,   count(l.amount) as loans_count
FROM
        loan as l
    INNER JOIN
        account a using (account_id)
    INNER JOIN
        disp as d using (account_id)
    INNER JOIN
        client as c using (client_id)
WHERE True
    AND l.status IN ('A', 'C')
    AND d.type = 'OWNER'
GROUP BY c.gender, 2;

SELECT * FROM tmp_analysis;

-- SELECT SUM(loans_count) FROM tmp_analysis;

-- kto posiada więcej spłaconych pożyczek – kobiety czy mężczyźni?


SELECT
    gender
,   ROUND(((count_repaid_loans * 100)/606),2) as percentage_repaid_loans
FROM tmp_results;

SELECT
    gender,
    SUM(loans_count) as loans_count
FROM tmp_analysis
GROUP BY gender;


-- jaki jest średni wiek kredytobiorcy w zależności od płci?

SELECT
    gender
,   ROUND(avg(age),0) as avg_age
FROM tmp_analysis
GROUP BY gender;

# Analiza klienta cz. 2

DROP TABLE IF EXISTS tmp_district_analytics;
CREATE TEMPORARY TABLE tmp_district_analytics AS
SELECT
    d2.district_id
,    count(distinct c.client_id) as customer_amount
,    sum(l.amount) as loans_given_amount
,    count(l.amount) as loans_given_count
FROM
        loan as l
    INNER JOIN
        account a using (account_id)
    INNER JOIN
        disp as d using (account_id)
    INNER JOIN
        client as c using (client_id)
    INNER JOIN
        district as d2 on
            c.district_id = d2.district_id
WHERE True
    AND l.status IN ('A', 'C')
    AND d.type = 'OWNER'
GROUP BY d2.district_id;

-- w którym rejonie jest najwięcej klientów
SELECT
    *
FROM tmp_district_analytics
ORDER BY customer_amount DESC
LIMIT 1;

-- w którym rejonie zostało spłaconych najwięcej pożyczek ilościowo
SELECT
    *
FROM tmp_district_analytics
ORDER BY loans_given_count DESC
LIMIT 1;


-- w którym rejonie zostało spłaconych najwięcej pożyczek kwotowo
SELECT
    *
FROM tmp_district_analytics
ORDER BY loans_given_amount DESC
LIMIT 1;

# Analiza klienta cz. 3 - procentowy udział każdego regionu w całkowitej kwocie udzielonych pożyczek

WITH cte AS (
    SELECT d2.district_id,
           count(distinct c.client_id) as customer_amount,
           sum(l.amount)               as loans_given_amount,
           count(l.amount)             as loans_given_count
    FROM
            loan l
        INNER JOIN
            account a using (account_id)
        INNER JOIN
            disp d using (account_id)
        INNER JOIN
            client c using (client_id)
        INNER JOIN
            district d2 ON
                c.district_id = d2.district_id
    WHERE True
      AND l.status IN ('A', 'C')
      AND d.type = 'OWNER'
    GROUP BY d2.district_id
)
SELECT
    *,
    loans_given_amount*100 / SUM(loans_given_amount) OVER () AS share
FROM cte
ORDER BY share DESC;

# Selekcja cz. 1
# Klienci urodzeni po 1990 roku, ich saldo konta przekracza 1000, mają więcej niż5 pożyczek

SELECT
    c.client_id,
    sum(amount - payments) as client_balance,
    count(loan_id) as loans_amount
FROM loan l
         INNER JOIN
     account a USING (account_id)
         INNER JOIN
     disp  d USING (account_id)
         INNER JOIN
     client c USING (client_id)
WHERE True
  AND l.status IN ('A', 'C')
  AND d.type = 'OWNER'
  AND EXTRACT(YEAR FROM c.birth_date) > 1990
GROUP BY c.client_id
HAVING
    SUM(amount - payments) > 1000
    AND COUNT(loan_id) > 5; -- brak wyników, źle dobrane filtry

# Selekcja cz. 2. - sprawdzenie, przez który warunek nie ma wyników
                            SELECT
    c.client_id,
    sum(amount - payments) as client_balance,
    count(loan_id) as loans_amount
FROM loan l
         INNER JOIN
     account a USING (account_id)
         INNER JOIN
     disp  d USING (account_id)
         INNER JOIN
     client c USING (client_id)
WHERE True
  AND l.status IN ('A', 'C')
  AND d.type = 'OWNER'
 -- AND EXTRACT(YEAR FROM c.birth_date) > 1990 -- nie ma osobób urodzonych w 1990 r.
GROUP BY c.client_id
HAVING
    SUM(amount - payments) > 1000
--    AND COUNT(loan_id) > 5 -- każdy klient ma jedną pożyczkę
;

SELECT
    * ,
    EXTRACT(YEAR from birth_date)
FROM
    client
WHERE
    EXTRACT(YEAR from birth_date) = 1990;

# Wygasające karty

WITH cte AS (SELECT c2.client_id,
                    c.card_id,
                    -- liczymy datę wygaśnięcia zgodnie z warunkami zadania
                    DATE_ADD(c.issued, INTERVAL 3 year) as expiration_date,
                    d2.A3                               as client_adress
             FROM card c
                      INNER JOIN
                  disp d USING (disp_id)
                      INNER JOIN
                  client c2 USING (client_id)
                      INNER JOIN
                  district d2 USING (district_id))
SELECT *
FROM cte
-- teraz z pełnej listy kart wybieramy tylko te, które mają się niedługo przedawnić
WHERE '2000-01-01' BETWEEN DATE_ADD(expiration_date, INTERVAL -7 DAY) AND expiration_date;

# Stworzenie tabeli
CREATE TABLE cards_at_expiration
(
    client_id       int                      not null,
    card_id         int default 0            not null,
    expiration_date date                     null,
    A3              varchar(15) charset utf8 not null,
    generated_for_date date                     null
);

#Tworzenie procedury
DELIMITER $$
DROP PROCEDURE IF EXISTS generate_cards_at_expiration_report;
CREATE PROCEDURE generate_cards_at_expiration_report(p_date DATE)
BEGIN
    TRUNCATE TABLE cards_at_expiration;
    INSERT INTO cards_at_expiration
    WITH cte AS (
        SELECT c2.client_id,
               c.card_id,
               date_add(c.issued, interval 3 year) as expiration_date,
               d2.A3
        FROM
            card c
                 INNER JOIN
             disp d using (disp_id)
                 INNER JOIN
             client c2 using (client_id)
                 INNER JOIN
             district d2 using (district_id)
    )
    SELECT
           *,
           p_date
    FROM cte
    WHERE p_date BETWEEN DATE_ADD(expiration_date, INTERVAL -7 DAY) AND expiration_date
    ;
END; $$

# Sprawdzenie
CALL generate_cards_at_expiration_report('2001-01-01');
SELECT * FROM cards_at_expiration;


