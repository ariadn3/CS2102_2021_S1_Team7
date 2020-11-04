
CREATE OR REPLACE FUNCTION bid_search (petname VARCHAR, sd DATE, ed DATE)
RETURNS TABLE (userid VARCHAR) AS
$func$
BEGIN
  RETURN QUERY(
  ((
	SELECT ct_userid FROM PT_validpet pt WHERE pt.pet_type IN (
		SELECT pet_type FROM Pet p WHERE p.pet_name = petname)
	)INTERSECTION(
	SELECT ct_userid FROM PT_Availability
	WHERE sd >= avail_sd AND ed <= avail_ed
	)EXCEPT(SELECT exp.ctuser FROM explode_date(sd, ed) exp
	HAVING COUNT(*) >= CASE
	                    WHEN (SELECT avg(rating) FROM Looking_After la WHERE la.ct_userid = exp.ctuser) > 4 THEN 5
	                    ELSE 2
	                  END)
	)UNION(
	SELECT ct_userid FROM FT_validpet ft WHERE ft.pet_type IN(
		SELECT pet_type FROM Pet p WHERE p.pet_name = petname)
	EXCEPT(SELECT ct_userid FROM FT_Leave
	          WHERE NOT ((sd < leave_sd AND ed < leave_sd) OR (sd > leave_ed AND sd > leave_ed)))
	EXCEPT(
	SELECT ctuser FROM explode_date(sd, ed)
	GROUP BY ctuser, day DESC
	HAVING COUNT(*) = 5
	)))
;
END;
$func$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION bidDetails (userid VARCHAR)
RETURNS TABLE (name VARCHAR, avgrating FLOAT, price FLOAT) AS
$func$
BEGIN
RETURN QUERY(
	SELECT Users.name AS name, AVG(rating) AS avgrating, ftpt.price AS price
	FROM Users INNER JOIN Looking_After ON Users.userid = Looking_After.ct_userid
		INNER JOIN 
		(
		SELECT ct_userid, pet_type FROM PT_validpet pt
		UNION
		SELECT ct_userid, pet_type FROM FT_validpet ft
		) ftpt ON Users.userid = ftpt.ct_userid
		WHERE ftpt.userid IN userid
	GROUP BY ftpt.userid
	);
END;
$func$
LANGUAGE plpgsql;

------- DELETE ABOVE======



-- Page 1
CREATE OR REPLACE FUNCTION login(username VARCHAR, pw VARCHAR)
RETURNS BOOLEAN AS
$func$
BEGIN
	RETURN(SELECT EXISTS(
		SELECT 1 FROM Accounts a
		WHERE login.username = a.userid AND login.pw = a.password
			));
END;
$func$
LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION user_type(userid VARCHAR)
-- 1: PO
-- 2: CTPT    4: CTFT
-- 3: CTPT+PO  5: CTFT+PO
-- 0: None
RETURNS INTEGER AS
$func$
DECLARE acc_type INTEGER = 0;
BEGIN
  IF (SELECT EXISTS(SELECT 1 FROM Pet_Owner po WHERE po.po_userid = user_type.userid) THEN acc_type = acc_type + 1;
  END IF; -- +1 if PO
  IF (SELECT EXISTS(SELECT 1 FROM PT_validpet pt WHERE pt.ct_userid = user_type.userid) THEN acc_type = acc_type + 2;
  END IF; -- +2 if CTPT
  IF (SELECT EXISTS(SELECT 1 FROM FT_validpet ft WHERE ft.ct_userid = user_type.userid) THEN acc_type = acc_type + 4;
  END IF; -- +4 if CTFT
	RETURN(acc_type);
END;
$func$
LANGUAGE plpgsql;


-- Page 2,3
CREATE OR REPLACE PROCEDURE signup(userid VARCHAR, name VARCHAR, postal INT, address VARCHAR, hp INT, email VARCHAR, pw VARCHAR) AS
$func$ 
--function run on page 3, data input on pg 2 and 3
BEGIN
  IF (  -- for reactivating their acc
        signup.userid, signup.email, signup.name IN (SELECT u.userid, u.email, u.name FROM Users u)
        UPDATE Accounts
        SET Accounts.deactivate = FALSE
        WHERE Accounts.userid = signup.userid
  )
  ELSE ( -- completely new acc
        INSERT INTO Accounts VALUES (signup.userid, signup.pw, FALSE)
        INSERT INTO Users VALUES (signup.userid, signup.name, signup.postal, signup.address, signup.hp, signup.email)
  );
END;
$func$
LANGUAGE plpgsql;



-- Page 4
CREATE OR REPLACE PROCEDURE updateProfile(userid VARCHAR, address VARCHAR, postalcode INT, hpnumber INT) AS
$func$
BEGIN
	UPDATE Users
	SET postal = postalcode, address = address, hp = hpnumber
	WHERE userid = userid;
END;
$func$
LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE editPW(userid VARCHAR, pw VARCHAR) AS
$func$
BEGIN
	UPDATE Accounts
	SET pw = pw
	WHERE userid = userid;
END;
$func$
LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE addPTPetsICanCare(userid VARCHAR, pettype VARCHAR, price FLOAT) AS
$func$ --call different function in python depending on pt/ft
BEGIN
  INSERT INTO PT_validpet VALUES (userid, pettype, price)
END;
$func$
LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE deletePTPetsICanCare(userid VARCHAR, pettype VARCHAR, price FLOAT) AS
$func$ --call different function in python depending on pt/ft
BEGIN
  DELETE FROM PT_validpet VALUES ct_userid = userid, pet_type = pettype, price = price)
END;
$func$
LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE addFTPetsICanCare(userid VARCHAR, pettype VARCHAR) AS
$func$ --call different function in python depending on pt/ft
BEGIN
  INSERT INTO FT_validpet VALUES (userid, pettype)
END;
$func$
LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE deleteFTPetsICanCare(userid VARCHAR, pettype VARCHAR, price FLOAT) AS
$func$ --call different function in python depending on pt/ft
BEGIN
  DELETE FROM FT_validpet VALUES ct_userid = userid, pet_type = pettype)
END;
$func$
LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE deleteacc(userid VARCHAR) AS
$func$
BEGIN
  UPDATE Accounts
  SET deactivate = TRUE
  WHERE userid = userid;
END;
$func$
LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE addPOpets(userid VARCHAR, petname VARCHAR, bday VARCHAR, specreq VARCHAR, pettype VARCHAR) AS
$func$
BEGIN
	INSERT INTO Pet (po_userid, pet_name, dead, birthday, spec_req, pet_type) VALUES (userid, petname, 0, bday, specreq, pettype);
END;
$func$
LANGUAGE plpgsql;

--------- !!!! im not too sure for this - nik
CREATE OR REPLACE PROCEDURE editPOpets(userid VARCHAR, petname VARCHAR, bday VARCHAR, specreq VARCHAR, pettype VARCHAR, dieded INTEGER) AS
$func$ 
-- dead = 1 if have change. Need to check if it works, especially if you change name + update dead at same time
-- dieded value should be 0 or 1. Too lazy to change this to boolean sry
-- deletepet will be done by this too. Or should we split?
BEGIN
	UPDATE Pet
	SET pet_name = petname, birthday = bday, spec_req = specreq, pet_type = pettype, dead = (SELECT max(dead)+dieded FROM Pet WHERE po_userid = userid AND pet_name = petname)
	WHERE po_userid = userid, pet_name = petname;
END;
$func$
LANGUAGE plpgsql;
----------

CREATE OR REPLACE PROCEDURE editBank(userid VARCHAR, bankacc INT) AS
$func$
BEGIN
  REPLACE INTO Caretaker(ct_userid, bank_acc) VALUES (userid, bankacc)
END;
$func$
LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE editCredit(userid VARCHAR, credcard INT) AS
$func$
BEGIN
  REPLACE INTO Pet_Owner(po_userid, credit) VALUES (userid, credcard)
END;
$func$
LANGUAGE plpgsql;



-- Page 5
-- settled
CREATE OR REPLACE FUNCTION po_upcoming_bookings(userid VARCHAR)
RETURNS TABLE (pet_name VARCHAR, ct_userid VARCHAR, start_date DATE, end_date DATE, status VARCHAR) AS
$func$
BEGIN
  RETURN QUERY(
	SELECT a.pet_name, a.ct_userid, a.start_date, a.end_date, a.status FROM Looking_After a
	WHERE a.po_userid = userid AND a.status != 'Rejected' AND a.status != 'Completed');
END;
$func$
LANGUAGE plpgsql;
--


CREATE OR REPLACE FUNCTION explode_date (sd DATE, ed DATE)
--takes in start date, end date. outputs every single day, with each caretaker booked on that day and what pet they looking after
--get the count of pets by doing groupby day, user.
--for use in bidsearch function when checking # of pets booked for each caretaker
RETURNS TABLE (ctuser VARCHAR, pouser VARCHAR, petname VARCHAR, day DATE) AS
$func$
BEGIN
--DECLARE @minDT DATE, @maxDT Date
--SELECT @minDt =  MIN(start_date) , @,axDt = MAX(end_date) --date range of upcoming accepted pet jobs
--FROM Looking_After WHERE status = 'Accepted'
--delete the above 3 lines if this functions works and doesn't need to be fixed
DECLARE @runDT DATE
SELECT @runDT = sd
DECLARE @exploded_table TABLE(ctuser VARCHAR, pouser VARCHAR, petname VARCHAR, dateday DATE)

WHILE @runDT <= ed
BEGIN
  INSERT INTO @exploded_table (ctuser, pouser, petname, dateday) SELECT la.ct_userid, la.po_userid, la.pet_name, @runDT FROM Looking_After la WHERE la.start_date <= @runDT AND la.end_date >= @runDT
  SET @runDT = @runDT + 1
END
RETURN QUERY(SELECT * FROM @exploded_table);
END;
$func$
LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION bid_search (petname VARCHAR, sd DATE, ed DATE)
RETURNS TABLE (userid VARCHAR) AS
$func$
BEGIN
  RETURN QUERY(
  ((
	SELECT ct_userid FROM PT_validpet pt WHERE pt.pet_type IN ( -- PTCT who can care for this pettype
		SELECT pet_type FROM Pet p WHERE p.pet_name = petname)
	)INTERSECT(
	SELECT ct_userid FROM PT_Availability -- Available PTCT
	WHERE sd >= avail_sd AND ed <= avail_ed
	)EXCEPT(SELECT exp.ctuser FROM explode_date(sd, ed) exp -- REMOVE from available PTCT those who are fully booked
	GROUP BY ctuser, day DESC
	HAVING COUNT(*) >= CASE --define 4 as good rating
	                    WHEN (SELECT avg(rating) FROM Looking_After la WHERE la.ct_userid = exp.ctuser) > 4 THEN 5
	                    ELSE 2
	                  END)
	)UNION(
	SELECT ct_userid FROM FT_validpet ft WHERE ft.pet_type IN( --FTCT who can care for this pettype
		SELECT pet_type FROM Pet p WHERE p.pet_name = petname)
	EXCEPT(SELECT ct_userid FROM FT_Leave -- Remove FT who are unavailable. Check that this part works, not sure if logic correct
	          WHERE NOT ((sd < leave_sd AND ed < leave_sd) OR (sd > leave_ed AND sd > leave_ed)))
	EXCEPT(--Remove FT caretakers who have 5 pets at any day in this date range
	SELECT ctuser FROM explode_date(sd, ed)
	GROUP BY ctuser, day DESC
	HAVING COUNT(*) = 5
	))
	)
;
END;
$func$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION bidDetails (userid VARCHAR) 
--Bidsearchuserid and bidDetails are used for page
--6 output. so pg 6 will be sth like bidDetails(bidsearchuserid(petname, sd, ed))
RETURNS TABLE (name VARCHAR, avgrating FLOAT, price FLOAT) AS
$func$
BEGIN
RETURN QUERY(
	SELECT Users.name AS name, AVG(rating) AS avgrating, ftpt.price AS price
	FROM Users INNER JOIN Looking_After ON Users.userid = Looking_After.ct_userid
		INNER JOIN 
		(
		SELECT ct_userid, pet_type FROM PT_validpet pt
		UNION
		SELECT ct_userid, pet_type FROM FT_validpet ft
		) ftpt ON Users.userid = ftpt.ct_userid
		WHERE ftpt.userid IN userid
	GROUP BY ftpt.userid
	);
END;
$func$
LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION pastTransactions (userid VARCHAR)
RETURNS TABLE (name VARCHAR, pet_name FLOAT, start_date DATE, end_date DATE) AS
$func$
BEGIN
RETURN QUERY(
	SELECT ct_userid AS name, pet_name, start_date, end_date
	FROM Looking_After
	WHERE (po_userid = userid OR ct_userid = userid) AND status = 'Completed'
	);
END;
$func$
LANGUAGE plpgsql;



-- Page 6
CREATE OR REPLACE FUNCTION caretakerReviewRatings (userid VARCHAR)
RETURNS TABLE (review VARCHAR, rating INTEGER) AS
$func$
BEGIN
RETURN QUERY(
	SELECT review, rating
	FROM Looking_After
	WHERE ct_userid = userid AND status = 'Completed'
	);
END;
$func$
LANGUAGE plpgsql;


-- Page 8
CREATE OR REPLACE PROCEDURE applyBooking (pouid VARCHAR, petname VARCHAR, ctuid VARCHAR, sd DATE, ed DATE, price FLOAT, payment_op VARCHAR) AS
$func$
BEGIN
  INSERT INTO Looking_After (po_userid, ct_userid, pet_name, start_date, end_date, trans_pr, payment_op)
  VALUES (pouid, ctuid, petname, sd, ed, price, payment_op);
END;
$func$
LANGUAGE plpgsql;


-- Page 9
CREATE OR REPLACE FUNCTION all_your_transac(userid VARCHAR)
RETURNS TABLE (ct_userid VARCHAR, po_userid VARCHAR, pet_name VARCHAR, start_date DATE, end_date DATE, status VARCHAR, rating FLOAT) AS
$func$
BEGIN
RETURN QUERY(
	SELECT ct_userid, po_userid, pet_name, start_date, end_date, status, rating FROM Looking_After
	WHERE po_userid = userid OR ct_userid = userid
	);
END;
$func$
LANGUAGE plpgsql;



-- Page 10
CREATE OR REPLACE FUNCTION ct_reviews(userid VARCHAR)
RETURNS TABLE (ct_userid VARCHAR, po_userid VARCHAR, pet_name VARCHAR, start_date DATE, end_date DATE, status VARCHAR, rating FLOAT, review VARCHAR) AS
$func$
BEGIN
RETURN QUERY(
	SELECT la.ct_userid, la.po_userid, la.pet_name, la.start_date, la.end_date, la.status, la.rating, la.review FROM Looking_After la
	WHERE la.ct_userid = ct_reviews.userid
	);
END;
$func$
LANGUAGE plpgsql;



-- Page 11
CREATE OR REPLACE PROCEDURE write_review_rating(userid VARCHAR, pet_name VARCHAR, ct_userid VARCHAR, start_date DATE, end_date DATE, rating INTEGER, review VARCHAR) AS
$func$
BEGIN
  UPDATE Looking_After la
  SET la.rating=write_review_rating.rating, la.review=write_review_rating.review
	WHERE la.po_userid = write_review_rating.userid AND la.ct_userid = write_review_rating.ct_userid AND la.start_date = wrote_review_rating.start_date AND la.end_date = write_review_rating.end_date;
END;
$func$
LANGUAGE plpgsql;



-- Page 12
CREATE OR REPLACE FUNCTION ftpt_upcoming(userid VARCHAR) --ft and pt both use same function. Possible problems if FT becomes PT or vice versa? Or we just assume they can't do that
RETURNS TABLE (ct_userid VARCHAR, petname VARCHAR, start_date DATE, end_date DATE) AS
$func$
BEGIN
RETURN QUERY(
	SELECT la.ct_userid, la.pet_name, la.start_date, la.end_date FROM Looking_After la
	WHERE la.ct_userid = ftpt_upcoming.userid AND la.status = 'ACCEPTED'
	);
END;
$func$
LANGUAGE plpgsql;



-- Page 13
CREATE OR REPLACE PROCEDURE ft_applyleave(userid VARCHAR, sd DATE, ed DATE) AS
$func$ --TODO: add a check for if FT has taken too much leave, 
--cannot apply leave if >=1 pet under their care

--search from ft_leave sd to ed, if userid alredy
BEGIN
  IF --condition to check if pet under their care
    INSERT INTO FT_Leave VALUES (ft_applyleave.userid, ft_applyleave.sd, ft_applyleave.ed);
  END IF;
END;
$func$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION ft_upcomingapprovedleave(userid VARCHAR)
RETURNS TABLE (leave_sd DATE, leave_ed DATE) AS
$func$
BEGIN
RETURN QUERY(
	SELECT ftl.leave_sd, ftl.leave_ed FROM FT_Leave ftl
	WHERE ftl.ct_userid = ft_upcomingapprovedleave.userid
	);
END;
$func$
LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE ft_cancelleave(userid VARCHAR, sd DATE, ed DATE) AS
$func$
BEGIN
  DELETE FROM FT_Leave ft
  WHERE ft.ct_userid = ft_cancelleave.userid AND ft.avail_sd = ft_cancelleave.sd AND ft.avail_ed = ft_cancelleave.ed;
END;
$func$
LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE pt_applyavail(userid VARCHAR, sd DATE, ed DATE) AS
$func$ --Checks that PT is applying availability within the next 2 years
BEGIN --CURRENT_DATE() is builtin sql function returning current date
  IF EXTRACT(YEAR FROM CURRENT_DATE()) - EXTRACT(YEAR FROM pt_applyavail.sd) BETWEEN 0 AND 1 THEN
    INSERT INTO PT_Availability VALUES (pt_applyavail.userid, pt_applyavail.sd, pt_applyavail.ed);
  END IF;
END;
$func$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pt_upcomingavail(userid VARCHAR)
RETURNS TABLE (avail_sd DATE, avail_ed DATE) AS
$func$
BEGIN
RETURN QUERY(
	SELECT pta.avail_sd, pta.avail_ed FROM PT_Availability pta
	WHERE pta.ct_userid = pt_upcomingavail.userid
	);
END;
$func$
LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE ptft_del_date(userid VARCHAR, sd DATE, ed DATE) AS
$func$ -- No need to check which table user is in, just delete from both pt and ft tables
-- TODO: Maybe delete, this function sucks
DECLARE @pt_booked BOOLEAN;
BEGIN
  DELETE FROM FT_Leave ft WHERE ft.ct_userid = ptft_del_date.userid AND ft.leave_sd = ptft_del_date.sd AND ft.leave_ed = ptft_del_date.ed;
  
  (
  SELECT CAST(COUNT(*) AS bit) INTO pt_booked -- CAST as boolean value indicating existence of bookings
  FROM Looking_After la
  WHERE la.ct_userid = ptft_del_date.userid AND ptft_del_date.sd <= la.start_date AND ptft_del_date.ed >= la.end_date AND la.status = 'Pending'
  
  IF pt_booked THEN
    DELETE FROM PT_Availability pt WHERE pt.ct_userid = ptft_del_date.userid AND pt.avail_sd = ptft_del_date.sd AND pt.avail_ed = ptft_del_date.ed;
  END IF;
  )
END;
$func$
LANGUAGE plpgsql;

-- Page 14
-- TODO: THIS FUNCTION MAY BE DELETED
CREATE OR REPLACE FUNCTION pastsalary(userid VARCHAR)
RETURNS TABLE (year INT, month INT, salary FLOAT) AS
$func$
BEGIN
RETURN QUERY(
  SELECT s.year, s.month, sum(s.amount) as salary
  FROM Salary s
	WHERE s.ct_userid = ptft_del_date.userid
	GROUP BY s.year ASC, s.month ASC
	);
END;
$func$
LANGUAGE plpgsql;



-- Page 15
CREATE OR REPLACE FUNCTION total_trans_pr_mnth(userid VARCHAR, year INT, month INT)
RETURNS FLOAT
$func$
BEGIN
  DECLARE @firstday DATE := cast(cast(total_trans_pr_mnth.year AS VARCHAR) + '-' + cast(total_trans_pr_mnth.month AS VARCHAR) + '-01' AS date)
  DECLARE @lastday DATE := cast(cast(total_trans_pr_mnth.year AS VARCHAR) + '-' + cast((total_trans_pr_mnth.month+1) AS VARCHAR) + '-01' AS date)

  RETURN QUERY(
  (SELECT sum(la.trans_pr)
  FROM Looking_After la
  WHERE total_trans_pr_mnth.userid = la.ct_userid
  AND (la.start_date >= firstday AND la.end_date <= lastday
  AND la.status = 'Completed') --Transaction occurs completely in this month
  +
  (SELECT sum(lab.trans_pr * (lab.end_date - firstday)/(lab.end_date - lab.start_date)) -- Multiplies trans_pr by no. of days that transaction was in this month
  FROM Looking_After lab
  WHERE total_trans_pr_mnth.userid = lab.ct_userid
  AND (lab.start_date < firstday AND lab.end_date <= lastday AND lab.end_date >= firstday)
  AND lab.status = 'Completed') --Transaction starts before this month, but ends during
  +
  (SELECT sum(lac.trans_pr * (lastday - lac.start_date)/(lac.end_date - lac.start_date)) -- Multiplies trans_pr by no. of days that transaction was in this month
  FROM Looking_After lac
  WHERE total_trans_pr_mnth.userid = lac.ct_userid
  AND (lac.start_date <= lastday AND lac.start_date >= firstday AND lac.end_date > lastday)
  AND lac.status = 'Completed') --Transaction starts during this month, but ends after
  +
  (SELECT sum(lad.trans_pr * (lastday - firstday)/(lad.end_date - lad.start_date))
  FROM Looking_After lad
  WHERE total_trans_pr_mnth.userid = lad.ct_userid
  AND (lad.start_date < firstday AND lad.end_date > lastday
  AND lad.status = 'Completed') --Transaction covers whole month, but starts before and ends after
  ); --TODO: maybe delete if we confirm max transactions 2 weeks
END;
$func$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION total_pet_day_mnth(userid VARCHAR, year INT, month INT)
RETURNS INT
$func$
BEGIN
  DECLARE @firstday DATE := cast(cast(total_pet_day_mnth.year AS VARCHAR) + '-' + cast(total_pet_day_mnth.month AS VARCHAR) + '-01' AS date)
  DECLARE @lastday DATE := cast(cast(total_pet_day_mnth.year AS VARCHAR) + '-' + cast((total_pet_day_mnth.month+1) AS VARCHAR) + '-01' AS date)

  RETURN QUERY(
  (SELECT sum(EXTRACT(DAY FROM la.end_date - la.start_date))
  FROM Looking_After la
  WHERE total_pet_day_mnth.userid = la.ct_userid
  AND (la.start_date >= firstday AND la.end_date <= lastday
  AND la.status = 'Completed') --Transaction occurs completely in this month
  +
  (SELECT sum(EXTRACT(DAY FROM lab.end_date - firstday))
  FROM Looking_After lab
  WHERE total_pet_day_mnth.userid = lab.ct_userid
  AND (lab.start_date < firstday AND lab.end_date <= lastday AND lab.end_date >= firstday)
  AND lab.status = 'Completed') --Transaction starts before this month, but ends during
  +
  (SELECT sum(EXTRACT(DAY FROM lastday - lac.start_date))
  FROM Looking_After lac
  WHERE total_pet_day_mnth.userid = lac.ct_userid
  AND (lac.start_date <= lastday AND lac.start_date >= firstday AND lac.end_date > lastday)
  AND lac.status = 'Completed') --Transaction starts during this month, but ends after
  +
  (SELECT sum(lastday - firstday)
  FROM Looking_After lad
  WHERE total_pet_day_mnth.userid = lad.ct_userid
  AND (lad.start_date < firstday AND lad.end_date > lastday
  AND lad.status = 'Completed') --Transaction covers whole month, but starts before and ends after
  ); --TODO: maybe delete if we confirm max transactions 2 weeks
END;
$func$
LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION trans_this_month(userid VARCHAR, year INT, month INT)
RETURNS TABLE (po_userid VARCHAR, pet_name VARCHAR, start_date DATE, end_date DATE, rate FLOAT, trans_pr FLOAT) AS
$func$
BEGIN
  DECLARE @firstday DATE := cast(cast(trans_this_month.year AS VARCHAR) + '-' + cast(trans_this_month.month AS VARCHAR) + '-01' AS date)
  DECLARE @lastday DATE := cast(cast(trans_this_month.year AS VARCHAR) + '-' + cast((trans_this_month.month+1) AS VARCHAR) + '-01' AS date)
RETURN QUERY(
  SELECT la.po_userid, la.pet_name, la.start_date, la.end_date, la.trans_pr/(la.end_date - la.start_date) AS rate, la.trans_pr
  FROM Looking_After la
  WHERE la.ct_userid = trans_this_month.userid
  AND NOT (la.start_date < firstday AND la.end_date < firstday)
  AND NOT (la.start_date > lastday AND la.end_date > lastday)
  AND la.status = 'Completed'
  );
END;
$func$
LANGUAGE plpgsql;



-- Page 16
CREATE OR REPLACE FUNCTION petprofile(userid VARCHAR, petname VARCHAR)
RETURNS TABLE (pet_type VARCHAR, birthday DATE, spec_req VARCHAR) AS
$func$
BEGIN
RETURN QUERY(
  SELECT p.pet_type, p.birthday, p.spec_req FROM Pet p
  WHERE p.po_userid = petprofile.userid AND p.petname = petprofile.petname AND p.dead = 0
  );
END;
$func$
LANGUAGE plpgsql;


-- MISC
CREATE OR REPLACE PROCEDURE admin_modify_base(pet_type VARCHAR, price FLOAT) AS
$func$
BEGIN
  UPDATE Pet_Type
  SET Pet_Type.price = admin_modify_base.price
  WHERE Pet_Type.pet_type = admin_modify_base.pet_type;
END;
$func$
LANGUAGE plpgsql;

-- TRIGGERS
CREATE OR REPLACE FUNCTION check_pt_prices() --Raises PT prices, if admin increases base price
RETURNS TRIGGER AS
$$ BEGIN
  UPDATE pt
  SET pt.price = base.price
  FROM PT_validpet pt LEFT JOIN Pet_Type base ON pt.pet_type = base.pet_type
  WHERE pt.price < base.price
END;
$$
LANGUAGE plpgsql;

CREATE TRIGGER admin_change_price AFTER UPDATE ON Pet_Type
FOR EACH ROW EXECUTE PROCEDURE check_pt_prices;