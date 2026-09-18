"""
Synthetic data generator for the Preply breakage case study.

Placeholder only: mimics the schema described in the case (raw_payments,
raw_lessons, raw_students) so the dbt project can be built and tested before
the real dataset is available. Drop the real CSVs into ../seeds/ with the
same file names to replace this data — no downstream model should need to
change.

Point-in-time reference: DATASET_END below is "today" for the case (the
last day covered by the dataset). Payments whose cycle_end > DATASET_END
are still open and are the ones needing daily estimation.
"""

import random
from dataclasses import dataclass
from datetime import date, timedelta

import numpy as np
import pandas as pd

SEED = 42
random.seed(SEED)
np.random.seed(SEED)

DATASET_START = date(2024, 1, 15)
DATASET_END = date(2025, 1, 15)  # "today"
CYCLE_LENGTH_DAYS = 28

N_STUDENTS = 550

COUNTRIES = {
    # country: (weight, price_per_hour range)
    "US": (0.28, (14, 26)),
    "DE": (0.14, (13, 24)),
    "GB": (0.10, (13, 24)),
    "ES": (0.12, (8, 15)),
    "MX": (0.14, (7, 14)),
    "BR": (0.12, (7, 13)),
    "TR": (0.10, (6, 12)),
}

CHANNELS = ["paid_search", "organic", "referral", "social", "affiliate"]
CHANNEL_WEIGHTS = [0.32, 0.28, 0.18, 0.14, 0.08]

SUBJECTS = ["english", "spanish", "business_english", "math", "coding", "german", "exam_prep"]

PLAN_HOURS_OPTIONS = [4, 6, 8, 10, 12, 16, 20]
PLAN_HOURS_WEIGHTS = [0.12, 0.14, 0.22, 0.16, 0.14, 0.12, 0.10]

# Persona -> burn archetype. This is what drives *systematic* breakage
# differences between segments, so the dashboard has something real to show.
PERSONAS = {
    "diligent_professional": dict(weight=0.22, shape="steady", intensity=0.85),
    "exam_crammer": dict(weight=0.18, shape="back_loaded", intensity=0.75),
    "casual_hobbyist": dict(weight=0.25, shape="low_engagement", intensity=0.45),
    "power_learner": dict(weight=0.15, shape="front_loaded", intensity=0.95),
    "sporadic_traveler": dict(weight=0.20, shape="low_engagement", intensity=0.35),
}

CHURN_PROB_BY_CYCLE = {1: 0.30, 2: 0.22}  # cycle_number -> prob of not renewing after it
CHURN_PROB_DEFAULT = 0.15


@dataclass
class Student:
    student_id: str
    country: str
    signup_date: date
    acquisition_channel: str
    persona: str
    first_subject: str
    price_per_hour: float


def weighted_choice(options: dict):
    keys = list(options.keys())
    weights = [options[k][0] if isinstance(options[k], tuple) else options[k]["weight"] for k in keys]
    return random.choices(keys, weights=weights, k=1)[0]


def make_students(n: int) -> list[Student]:
    students = []
    span_days = (DATASET_END - DATASET_START).days
    for i in range(1, n + 1):
        country = weighted_choice(COUNTRIES)
        lo, hi = COUNTRIES[country][1]
        persona = weighted_choice(PERSONAS)
        # Signups spread across the window; a small tail near the end so we
        # get plenty of payments still inside their first, still-open cycle.
        offset = int(np.random.triangular(0, span_days * 0.7, span_days))
        signup = DATASET_START + timedelta(days=offset)
        students.append(
            Student(
                student_id=f"STU{i:05d}",
                country=country,
                signup_date=signup,
                acquisition_channel=random.choices(CHANNELS, weights=CHANNEL_WEIGHTS, k=1)[0],
                persona=persona,
                first_subject=random.choice(SUBJECTS),
                price_per_hour=round(random.uniform(lo, hi), 2),
            )
        )
    return students


def daily_booking_probability(day_in_cycle: int, shape: str, intensity: float) -> float:
    """Rough probability a booking happens on a given cycle day, by archetype."""
    t = day_in_cycle / (CYCLE_LENGTH_DAYS - 1)  # 0..1
    if shape == "steady":
        base = 0.30
    elif shape == "front_loaded":
        base = 0.55 * (1 - t) + 0.05
    elif shape == "back_loaded":
        base = 0.10 + 0.55 * t
    elif shape == "low_engagement":
        base = 0.12
    else:
        base = 0.25
    return float(np.clip(base * intensity, 0.02, 0.95))


def simulate_cycle_bookings(plan_hours: int, cycle_start: date, cycle_end_exclusive: date,
                             sim_horizon: date, shape: str, intensity: float):
    """Returns list of (booking_date, hours_booked) within [cycle_start, min(cycle_end, horizon))."""
    bookings = []
    remaining = plan_hours
    last_day = min(cycle_end_exclusive, sim_horizon + timedelta(days=1))
    n_days = (last_day - cycle_start).days
    for d in range(max(n_days, 0)):
        if remaining <= 0:
            break
        booking_date = cycle_start + timedelta(days=d)
        p = daily_booking_probability(d, shape, intensity)
        if random.random() < p:
            hours = min(remaining, random.choice([1, 1, 1, 2, 2, 3]))
            bookings.append((booking_date, hours))
            remaining -= hours
    return bookings


def main():
    students = make_students(N_STUDENTS)

    payments_rows = []
    lessons_rows = []
    payment_seq = 1
    lesson_seq = 1

    for s in students:
        persona_cfg = PERSONAS[s.persona]
        cycle_start = s.signup_date
        cycle_number = 1
        plan_hours = random.choices(PLAN_HOURS_OPTIONS, weights=PLAN_HOURS_WEIGHTS, k=1)[0]

        while cycle_start <= DATASET_END:
            payment_id = f"PAY{payment_seq:06d}"
            payment_seq += 1
            payments_rows.append(
                dict(
                    payment_id=payment_id,
                    student_id=s.student_id,
                    payment_date=cycle_start.isoformat(),
                    plan_hours=plan_hours,
                    price_per_hour=s.price_per_hour,
                )
            )

            cycle_end_exclusive = cycle_start + timedelta(days=CYCLE_LENGTH_DAYS)
            bookings = simulate_cycle_bookings(
                plan_hours=plan_hours,
                cycle_start=cycle_start,
                cycle_end_exclusive=cycle_end_exclusive,
                sim_horizon=DATASET_END,
                shape=persona_cfg["shape"],
                intensity=persona_cfg["intensity"],
            )
            for booking_date, hours in bookings:
                lessons_rows.append(
                    dict(
                        lesson_id=f"LES{lesson_seq:07d}",
                        student_id=s.student_id,
                        payment_id=payment_id,  # convenience column; not in original spec, see README
                        booking_date=booking_date.isoformat(),
                        hours_booked=hours,
                    )
                )
                lesson_seq += 1

            cycle_closed = cycle_end_exclusive <= DATASET_END
            if not cycle_closed:
                break  # this is the open cycle; stop generating for this student

            churn_prob = CHURN_PROB_BY_CYCLE.get(cycle_number, CHURN_PROB_DEFAULT)
            if random.random() < churn_prob:
                break  # student doesn't renew

            # small chance of changing plan size on renewal
            if random.random() < 0.12:
                plan_hours = random.choices(PLAN_HOURS_OPTIONS, weights=PLAN_HOURS_WEIGHTS, k=1)[0]

            cycle_start = cycle_end_exclusive
            cycle_number += 1

    students_df = pd.DataFrame(
        [
            dict(
                student_id=s.student_id,
                country=s.country,
                signup_date=s.signup_date.isoformat(),
                acquisition_channel=s.acquisition_channel,
                persona=s.persona,
                first_subject=s.first_subject,
            )
            for s in students
        ]
    )
    payments_df = pd.DataFrame(payments_rows)
    lessons_df = pd.DataFrame(lessons_rows)

    # raw_lessons in the real dataset is described as booking_date + hours_booked
    # keyed by student, not by payment (the case says we must *derive* the
    # cycle/payment mapping ourselves). Drop payment_id here to force the
    # intermediate layer to do that mapping, same as with real data.
    lessons_df_public = lessons_df.drop(columns=["payment_id"])

    out_dir = "/home/user/dbt_learning/preply_breakage/seeds"
    students_df.to_csv(f"{out_dir}/raw_students.csv", index=False)
    payments_df.to_csv(f"{out_dir}/raw_payments.csv", index=False)
    lessons_df_public.to_csv(f"{out_dir}/raw_lessons.csv", index=False)

    print(f"students: {len(students_df)}")
    print(f"payments: {len(payments_df)}")
    print(f"lessons:  {len(lessons_df_public)}")
    print(f"dataset window: {DATASET_START} .. {DATASET_END}")


if __name__ == "__main__":
    main()
