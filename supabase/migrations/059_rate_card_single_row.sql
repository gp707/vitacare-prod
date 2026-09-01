-- Rate Card grids drop down to a single row ("Care") for both daily and
-- monthly — the "Nursing students/Nursing with backlogs" and "Nurses
-- (Nursing completed/Registered/Unregistered)" rows are no longer needed.
-- Keeps only the first row's label/cells; row_labels/cells stay TEXT[]/JSONB,
-- just with 1 entry instead of 3 going forward.
UPDATE rate_card
SET row_labels = row_labels[1:1],
    cells = jsonb_build_array(cells -> 0)
WHERE frequency_of_care IN ('daily', 'monthly');
